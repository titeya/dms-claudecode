.pragma library

var strings = {
    "Claude Code Usage":
        { fr: "Utilisation Claude Code" },
    "Subscription":
        { fr: "Abonnement" },
    "5h Rate Window":
        { fr: "Fenêtre 5h" },
    "used":
        { fr: "utilisé" },
    "Resets in":
        { fr: "Réinitialise dans" },
    "Resetting...":
        { fr: "Réinitialisation..." },
    "7-Day Usage":
        { fr: "Utilisation 7 jours" },
    "sessions":
        { fr: "sessions" },
    "msgs":
        { fr: "msgs" },
    "Daily Activity":
        { fr: "Activité quotidienne" },
    "Token Consumption":
        { fr: "Consommation de tokens" },
    "Today":
        { fr: "Aujourd'hui" },
    "Week":
        { fr: "Semaine" },
    "Month":
        { fr: "Mois" },
    "Models This Week":
        { fr: "Modèles cette semaine" },
    "Since":
        { fr: "Depuis" },
    // Settings
    "Monitor your Claude Code subscription usage. Rate limits and subscription tier are detected automatically via the Anthropic API.":
        { fr: "Surveillez l'utilisation de votre abonnement Claude Code. Les limites et le type d'abonnement sont détectés automatiquement via l'API Anthropic." },
    "Refresh Interval":
        { fr: "Intervalle de rafraîchissement" },
    "How often to fetch usage data (seconds)":
        { fr: "Fréquence de mise à jour des données (secondes)" },
}

function tr(key, lang) {
    if (!lang || lang === "en" || !strings[key] || !strings[key][lang])
        return key
    return strings[key][lang]
}
