'use strict';
// Journal console horodaté (les actions importantes vont aussi dans MySQL : mdc_action_log)
const stamp = () => new Date().toISOString().replace('T', ' ').slice(0, 19);

module.exports = {
    info: (...a) => console.log(`[${stamp()}] [MDC Web]`, ...a),
    warn: (...a) => console.warn(`[${stamp()}] [MDC Web] ATTENTION :`, ...a),
    error: (...a) => console.error(`[${stamp()}] [MDC Web] ERREUR :`, ...a),
};
