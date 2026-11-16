# LiveView WebRTC — serveur relais (LiveKit) et TURN

Le LiveView montre aux dispatchers, en direct, l'écran **du jeu** des joueurs qu'ils choisissent (image du jeu
uniquement, capturée par la ressource `screenshot-basic` : ni bureau, ni autre fenêtre, ni son).

Deux voies, choisies automatiquement :

| Voie | Quand | Qualité | Charge |
|---|---|---|---|
| **Vidéo WebRTC** par un **serveur relais** (SFU LiveKit + TURN intégré) | `LIVEKIT_*` rempli dans `.env` | ~2 images/s, 640 × 360 (mosaïque) ou 1280 × 720 (agrandi), débit plafonné | le relais transporte la vidéo ; le site ne fait que signer des jetons |
| **Images JPEG** relayées par le site (repli) | relais non configuré, injoignable, ou publication impossible dans le NUI | 0,5 image/s en mosaïque, 2 images/s agrandi | le site relaie chaque image |

Le repli est automatique **joueur par joueur** : si le NUI d'un joueur ne peut pas joindre le relais, ses images
arrivent par le site, sans rien faire.

---

## 1. Architecture

```
                              (1) live:watch [joueurs]           (2) live.start + jeton ÉMETTEUR
 Navigateur du dispatcher ──── Socket.IO (session Discord) ────▶ Site Node.js ─── API (clé partagée) ───▶ Serveur FiveM (rp_mdc)
        ▲      │                  ◀── jetons LECTEUR ──         │  signe les jetons (LIVEKIT_API_SECRET)        │ TriggerClientEvent
        │      │                                                │  ferme les salles / retire les lecteurs       ▼
        │      │                                                │  (API serveur du relais)               Joueur regardé
        │      │                                                ▼                                          client/liveview.lua
        │      │                                        Serveur relais LiveKit                             screenshot-basic (image du jeu)
        │      └──── (3) WebRTC : abonnement (lecture seule) ──▶  SFU + TURN  ◀──── (3) WebRTC : publication ──── NUI du MDC
        │                                                         salle « mdc-live-<id joueur> »                 canevas → vidéo ~2 i/s
        └────────────────────── vidéo du joueur ─────────────────────┘
```

1. Le dispatcher coche des joueurs (mosaïque) ou détache un écran (incrustation, plein écran). Le site vérifie sa
   **session** (rôle Discord « Dispatch », revérifié régulièrement), **enregistre la consultation** dans le journal
   (`mdc_action_log`, action `live.view`, voie `webrtc` ou `images`) et lui renvoie **un jeton lecteur par joueur**.
2. Le site demande au serveur FiveM de faire diffuser ces joueurs, avec un **jeton émetteur** limité à la salle du
   joueur. Ordre renouvelé toutes les 8 s ; sans renouvellement, le jeu s'arrête seul (25 s).
3. Le NUI du MDC du joueur charge la bibliothèque WebRTC **seulement à ce moment-là** (`html/vendor/`), dessine chaque
   capture dans un canevas (image décodée entière avant d'être dessinée : jamais d'image à moitié tracée) et publie ce
   canevas en vidéo vers le relais. Le navigateur du dispatcher s'abonne à la salle du joueur.

**Une salle par joueur** (`mdc-live-<id serveur>`) : un jeton ne donne accès qu'à l'écran pour lequel il a été émis.

### Jetons

| Jeton | Qui | Droits | Validité |
|---|---|---|---|
| Lecteur | navigateur d'un dispatcher, après vérification de session et journalisation | salle d'**un** joueur, **abonnement seul**, pas de publication, participant **caché** | 2 min pour entrer (le relais renouvelle ensuite la connexion) |
| Émetteur | NUI du joueur regardé, via le serveur FiveM | salle de **ce** joueur, **publication seule**, aucun abonnement | 15 min, renvoyé toutes les 8 s tant que quelqu'un regarde |

Le secret `LIVEKIT_API_SECRET` ne quitte jamais le site (il n'est ni dans le jeu, ni dans le navigateur).

### Arrêts et retraits

- Le dispatcher arrête de regarder un joueur (décoche, masque, ferme l'incrustation ou la fenêtre) : le site le
  **retire de la salle côté relais** (pas seulement dans son navigateur) ;
- plus personne ne regarde un joueur : ordre d'arrêt au jeu, et la **salle est fermée** sur le relais ;
- rôle Discord retiré, déconnexion, onglet fermé : la session temps réel se ferme, le site retire ce dispatcher de
  toutes les salles ;
- joueur déconnecté : ses flux s'arrêtent, les tuiles l'indiquent.

### Plafonds

| Réglage | Par défaut | Effet |
|---|---|---|
| `LIVE_MAX_STREAMS` | 16 | joueurs diffusés en même temps (tous dispatchers confondus) ; au-delà : refus affiché |
| `LIVE_MAX_KBPS` | 900 | débit max d'un joueur affiché en grand (mosaïque : la moitié) |
| Taille / cadence | 640 × 360 à 2 i/s (mosaïque), 1280 × 720 à 2 i/s (agrandi) | fixées par le site ; le jeu les borne (320–1280 px, 1–4 i/s, 100–4000 kb/s) |

Côté joueur : aucune capture sans ordre, 0,00 ms hors LiveView (la boucle n'existe que pendant une diffusion).

### Indicateurs (tuiles et incrustations)

Pastille de fraîcheur (vert < 3,5 s, orange < 8 s, rouge au-delà), **images/s mesurées** à l'affichage,
**délai** (WebRTC : délai de réception mesuré par le navigateur ; images : temps d'envoi de la dernière image),
**résolution reçue**, qualité de liaison (WebRTC) et voie utilisée (`WebRTC` / `images`).

---

## 2. Installer le serveur relais (LiveKit)

LiveKit est un serveur WebRTC libre (Apache-2.0). Il tourne sur une machine **joignable depuis Internet** (les joueurs
et les dispatchers s'y connectent directement), idéalement **la même que le site** ou une petite VM à part
(1 vCPU / 1 Go suffisent pour 16 flux à 2 i/s).

### 2.1 Clés

Générez une clé et un secret (32 caractères au moins pour le secret) :

```bash
docker run --rm livekit/livekit-server generate-keys
# ou : node -e "console.log('APIk' + require('crypto').randomBytes(6).toString('hex'), require('crypto').randomBytes(32).toString('base64url'))"
```

Gardez-les **hors du dépôt** : dans `livekit.yaml` (sur le serveur relais) et dans le `.env` du site.

### 2.2 Configuration

Copiez [`deploy/livekit.yaml`](../deploy/livekit.yaml) sur le serveur relais, remplacez le domaine et les clés.
Points importants :

- `rtc.use_external_ip: true` : le relais annonce son IP publique ;
- `turn.enabled: true` avec `domain` et TLS sur **5349** (ou 443) : indispensable pour les dispatchers derrière un
  pare-feu d'entreprise / un réseau qui bloque l'UDP ;
- `room.empty_timeout` court : une salle sans personne disparaît vite.

### 2.3 Démarrage (Docker)

```bash
docker run -d --name livekit --restart unless-stopped --network host \
  -v /etc/livekit/livekit.yaml:/livekit.yaml livekit/livekit-server:v1.13.11 --config /livekit.yaml
```

(Fixez une version précise de l'image, testée chez vous.) Ou le binaire `livekit-server --config livekit.yaml`
(service systemd).

### 2.4 HTTPS / WSS

Les navigateurs et le NUI du jeu (page `https://cfx-nui-rp_mdc`) exigent **`wss://`**. Deux façons :

- **Reverse proxy** (Nginx, Caddy) : `https://live.exemple.fr` → `http://127.0.0.1:7880` avec WebSocket
  (`Upgrade`/`Connection`) ; le média, lui, passe directement par les ports ci-dessous ;
- ou le TLS intégré de LiveKit (voir sa documentation).

Exemple Caddy :

```
live.exemple.fr {
    reverse_proxy 127.0.0.1:7880
}
```

### 2.5 Pare-feu

| Port | Proto | Usage |
|---|---|---|
| 443 | TCP | `wss://` (signalisation, via le reverse proxy) |
| 7881 | TCP | média WebRTC en TCP (repli quand l'UDP est filtré) |
| 50000–60000 | UDP | média WebRTC (plage `rtc.port_range_*`) |
| 3478 | UDP | TURN/UDP (STUN compris) |
| 5349 | TCP | TURN/TLS (réseaux très filtrés : fonctionne comme du HTTPS) |

7880 (API HTTP du relais) reste **local** derrière le proxy.

### 2.6 STUN / TURN : pourquoi et comment

- **STUN** : chaque client découvre son adresse publique ; fourni par le relais (port 3478), rien à ajouter.
- **TURN** : quand une connexion directe UDP est impossible (NAT strict, réseau d'entreprise, 4G), le client passe
  **par le relais** en UDP 3478, ou en **TLS 5349** (ressemble à du HTTPS, passe presque partout). Le TURN intégré à
  LiveKit suffit : **aucun serveur coturn séparé** n'est nécessaire.
- Les jetons LiveKit donnent aussi l'accès TURN : pas d'identifiants TURN statiques à distribuer.
- TURN/TLS demande un certificat pour `turn.domain` (ex. `turn.exemple.fr`) : `cert_file` / `key_file` dans
  `livekit.yaml`, ou un équilibreur TLS devant le port 5349.

Vérification : <https://livekit.io/connection-test> (avec un jeton de test), ou dans le site : tuile en `WebRTC`
avec un délai affiché.

---

## 3. Relier le site

Dans le `.env` du site :

```
LIVEKIT_URL=wss://live.exemple.fr
LIVEKIT_API_KEY=APIxxxxxxxx
LIVEKIT_API_SECRET=(secret de 32 caractères ou plus)
# facultatif : API serveur du relais si elle n'est pas https://<même hôte> (ex. http://127.0.0.1:7880 si local)
LIVEKIT_API_URL=
LIVE_MAX_KBPS=900
LIVE_MAX_STREAMS=16
```

Redémarrez le site. Il ajoute lui-même l'adresse du relais à sa politique de sécurité (CSP `connect-src`).
Rien à changer côté FiveM : le jeton émetteur passe par l'API existante (`mdc_web_key`). Le serveur FiveM n'a **pas**
besoin de joindre le relais ; ce sont les **clients** (jeu et navigateurs) qui s'y connectent.

Sans `LIVEKIT_*`, le LiveView marche comme en 4.0 (images JPEG) : la voie WebRTC est un ajout, pas un prérequis.

---

## 4. Ce qui a été vérifié, et ce qui ne l'a pas été

Vérifié par des tests automatiques (site réel, vraie base, vrai code Lua du serveur, vrai NUI dans Chromium) :
signature et contenu des jetons (salle, droits, durée), journalisation des consultations, ordres envoyés au jeu
(taille, cadence, débit, passage mosaïque ↔ agrandi), arrêts, publication du canevas par le NUI (bibliothèque
simulée : une piste vidéo, sans simulcast, débit et cadence plafonnés, une image vidéo par capture, pas de
reconnexion au changement de mode, déconnexion à l'arrêt), repli JPEG quand le relais est injoignable.

**Non vérifié ici** : le transport réel de la vidéo par un serveur LiveKit et le TURN (aucun relais n'a pu être lancé
dans l'environnement de développement). À tester sur votre serveur avec la liste « LiveView » de
[MISE_A_JOUR_5.0.md](MISE_A_JOUR_5.0.md).
