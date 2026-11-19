# LiveView — vidéo WebRTC de l'écran des joueurs (MDC 6.0)

Le LiveView montre au dispatcher, **en vidéo fluide** (jusqu'à 30 images / s), l'écran de jeu des joueurs qu'il choisit.
Il est **écrit de zéro** (aucun relais vidéo externe, plus de LiveKit ni de `screenshot-basic`) et suit les techniques
utilisées par les ressources de capture FiveM : lecture du **rendu du jeu** comme une texture WebGL dans le NUI, piste
vidéo `canvas.captureStream()`, envoi en **WebRTC** pair à pair.

```
 Navigateur du dispatcher  ◄──────── vidéo WebRTC (DTLS-SRTP, direct ou par TURN) ────────  NUI du MDC (jeu du joueur)
          │ Socket.IO « / » (session + rôle)                                   Socket.IO « /live » (jeton) │
          └──────────────────────────────►  site Node.js : signalisation seule  ◄────────────────────────┘
                                                     │ API « live.start / live.stop »
                                                     ▼
                                       serveur FiveM (rp_mdc) : relaie l'ordre au joueur
```

## Déroulé

1. Le dispatcher coche un joueur (outil **LiveView**, ou **LIVE &lt;unité&gt;** dans la ligne de commande, ou le menu
   d'une unité). Le site vérifie sa session et son rôle Discord, **journalise la consultation** (`live.view`) et crée
   une **liaison** (identifiant aléatoire) entre ce dispatcher et ce joueur.
2. Le site demande au serveur FiveM de faire diffuser le joueur, avec un **jeton de diffusion** aléatoire (24 octets,
   valable tant que quelqu'un regarde, renouvelé toutes les 20 s). `client/liveview.lua` le transmet au NUI ; sans
   renouvellement pendant 45 s (site coupé), la diffusion s'arrête seule.
3. Le NUI (`html/liveview.js`) se connecte à l'espace Socket.IO **`/live`** du site avec ce jeton (rien d'autre ne
   l'ouvre), reçoit la configuration (serveurs ICE, qualité) et les liaisons à servir.
4. **Capture** : un canevas WebGL hors écran dessine à chaque image la texture du jeu (image du jeu seule : ni le MDC,
   ni le chat, ni les autres interfaces), à la taille maximale réglée (1280 × 720 par défaut, proportions de l'écran
   gardées), puis `captureStream(30)` en fait une piste vidéo (indice `motion`).
5. **WebRTC** : une `RTCPeerConnection` par liaison, en émission seule. Le jeu fait l'**offre**, le navigateur répond ;
   offre, réponse et candidats ICE passent par le site, **jamais la vidéo**. Codec préféré : H.264 (sinon VP8 / VP9).
6. **Qualité en direct** : mosaïque = image réduite de moitié, 20 i/s, 700 kb/s ; **agrandi** (bouton ⤢ ou double-clic
   sur la tuile, incrustation en plein écran) = pleine taille, 30 i/s, 3 Mb/s. Le changement se fait sur la liaison
   existante (`RTCRtpSender.setParameters`), **sans renégociation** ni coupure. Préférence **maintain-framerate** :
   sur un réseau faible, la netteté baisse avant la fluidité. Côté dispatcher, tampon de gigue réduit (40 ms).
7. **Plus personne ne regarde** : liaisons fermées des deux côtés, ordre `live.stop`, la capture s'arrête (GPU libéré).

Le pied de chaque tuile affiche en direct : images / s reçues, résolution, débit, aller-retour (ms), codec, **direct**
ou **TURN**, et la cadence réellement capturée par le jeu. Image figée plus de 5 s : redémarrage ICE automatique.

## Configuration (`.env` du site)

| Variable | Défaut | Rôle |
|---|---|---|
| `LIVE_PUBLIC_URL` | `PUBLIC_URL` | adresse du site vue depuis le jeu (**HTTPS** en production) |
| `LIVE_MAX_STREAMS` | 16 | joueurs diffusés en même temps |
| `LIVE_MAX_VIEWERS` | 4 | dispatchers par joueur (chaque dispatcher = un encodage vidéo chez le joueur) |
| `LIVE_STUN_URLS` | Google + Cloudflare | serveurs STUN |
| `LIVE_TURN_URLS` | — | serveur(s) TURN, ex. `turn:turn.exemple.fr:3478,turns:turn.exemple.fr:5349` |
| `LIVE_TURN_SECRET` | — | secret partagé coturn (`static-auth-secret`) : identifiants temporaires |
| `LIVE_TURN_USERNAME` / `LIVE_TURN_PASSWORD` | — | sinon : identifiants fixes |
| `LIVE_TURN_TTL` | 3600 | validité des identifiants temporaires (s) |
| `LIVE_RELAY_ONLY` | 0 | 1 : toujours par TURN (aucune IP échangée entre joueur et dispatcher) |
| `LIVE_MAX_WIDTH` / `LIVE_MAX_HEIGHT` | 1280 / 720 | taille maximale de la capture (jusqu'à 1920 × 1080) |
| `LIVE_FPS` | 30 | cadence de capture et de l'agrandi (10 à 60) |
| `LIVE_CODEC` | h264 | codec préféré (`h264`, `vp8`, `vp9`) |
| `LIVE_GRID_SCALE` / `LIVE_GRID_FPS` / `LIVE_GRID_KBPS` | 2 / 20 / 700 | mosaïque |
| `LIVE_FOCUS_KBPS` | 3000 | débit maximal de l'agrandi (kb/s) |
| `LIVE_ALLOWED_ORIGINS` | `https://cfx-nui-rp_mdc,nui://rp_mdc` | origines autorisées pour la connexion du jeu |

Côté FiveM : **rien à installer** (plus besoin de `screenshot-basic`). La ressource `rp_mdc` contient
`html/liveview.js` et `html/vendor/socket.io.min.js` (Socket.IO 4.8.1, licence MIT), chargés seulement au premier usage.

## Serveur TURN (conseillé)

Sans TURN, la liaison passe en direct pour la plupart des joueurs ; derrière certains réseaux (NAT symétrique, 4G,
entreprise), elle échoue. **coturn** (gratuit) règle ce cas :

```
# /etc/turnserver.conf
listening-port=3478
tls-listening-port=5349
fingerprint
use-auth-secret
static-auth-secret=<même valeur que LIVE_TURN_SECRET, 32 caractères aléatoires>
realm=turn.exemple.fr
cert=/etc/letsencrypt/live/turn.exemple.fr/fullchain.pem
pkey=/etc/letsencrypt/live/turn.exemple.fr/privkey.pem
min-port=49160
max-port=49200
no-multicast-peers
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
```

Ports à ouvrir sur le serveur TURN : **3478** (UDP + TCP), **5349** (TCP, TLS), **49160–49200** (UDP). Puis dans `.env` :
`LIVE_TURN_URLS=turn:turn.exemple.fr:3478,turns:turn.exemple.fr:5349` et `LIVE_TURN_SECRET=<le secret>`.
Le site signe des identifiants temporaires (`expiration:identité` + HMAC-SHA1 du secret) : le secret ne quitte jamais
le serveur.

## Sécurité et vie privée

- Seuls les dispatchers connectés **avec le rôle Discord** peuvent regarder ; chaque consultation est journalisée.
- Le jeu ne diffuse que sur **ordre du site** relayé par le serveur FiveM, avec un jeton aléatoire ; un jeton inconnu
  est refusé ; un joueur ne peut parler qu'aux liaisons **de son propre flux**, un dispatcher qu'à ses liaisons.
- Messages de signalisation vérifiés (type, taille : SDP ≤ 32 Ko, candidat ≤ 1 Ko) et limités en cadence.
- La vidéo est chiffrée de bout en bout du transport (DTLS-SRTP) ; elle ne passe ni par le site ni par le serveur
  FiveM. En pair à pair, joueur et dispatcher voient l'adresse IP l'un de l'autre : `LIVE_RELAY_ONLY=1` (avec TURN)
  l'évite.
- Seul le **rendu du jeu** est capturé (pas le bureau du joueur, pas les autres fenêtres).

## Performance

- Hors LiveView : **rien** ne tourne (ni capture, ni connexion) ; côté Lua, un minuteur n'existe que pendant une
  diffusion (0,00 ms sinon).
- Pendant une diffusion : un dessin WebGL par image (plafonné à `LIVE_FPS`) et un encodage vidéo **par dispatcher**
  qui regarde (d'où `LIVE_MAX_VIEWERS`). Pour un joueur regardé par plusieurs dispatchers en même temps sur un PC
  modeste, baissez `LIVE_MAX_WIDTH` / `LIVE_FPS`.

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| « Connexion à l'écran du joueur… » sans fin | site injoignable depuis le jeu ou origine refusée | `LIVE_PUBLIC_URL` en HTTPS accessible depuis Internet ; `LIVE_ALLOWED_ORIGINS` |
| liaison « échec » | NAT strict | serveur TURN (`LIVE_TURN_URLS`, `LIVE_TURN_SECRET`) |
| image noire | texture du jeu non reconnue (client FiveM très ancien) | mettre à jour FiveM ; tester `MDCLive.status()` dans la console NUI (F8 → `nui_devtools`) |
| saccades | débit ou PC du joueur limité | baisser `LIVE_FOCUS_KBPS`, `LIVE_MAX_WIDTH`, `LIVE_FPS` ; vérifier le pied de tuile (TURN / direct, i/s du jeu) |
| « Limite atteinte » | `LIVE_MAX_STREAMS` ou `LIVE_MAX_VIEWERS` | augmenter avec prudence |
