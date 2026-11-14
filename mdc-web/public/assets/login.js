// Pages de connexion / refus : message selon l'erreur (aucun script inline : CSP stricte)
(() => {
    'use strict';
    const params = new URLSearchParams(location.search);
    const errors = {
        cancelled: 'Connexion annulée sur Discord.',
        state: 'La connexion a expiré ou a été interrompue : recommencez.',
        discord: 'Discord ne répond pas pour le moment : réessayez dans un instant.',
        session: 'Impossible de créer la session : réessayez.',
    };
    const box = document.getElementById('authError');
    if (box && errors[params.get('error')]) {
        box.textContent = errors[params.get('error')];
        box.classList.remove('hidden');
    }
    const denied = document.getElementById('deniedText');
    const reasons = {
        guild: 'Votre compte Discord n\'est pas membre du serveur Discord de la communauté.',
        role: 'Votre compte Discord n\'a pas le rôle « Dispatch » sur le serveur Discord.',
        discord: 'Votre rôle n\'a pas pu être vérifié (Discord injoignable) : reconnectez-vous plus tard.',
        session: 'Votre session a expiré : reconnectez-vous.',
    };
    if (denied && reasons[params.get('reason')]) denied.textContent = reasons[params.get('reason')];
})();
