// Thème jour / nuit appliqué avant l'affichage (pas de flash) ; nuit par défaut, choix gardé dans ce navigateur
(() => {
    let theme = 'night';
    try { theme = localStorage.getItem('mdc.theme') === 'day' ? 'day' : 'night'; } catch (e) { /* stockage indisponible */ }
    document.documentElement.dataset.theme = theme;
})();
