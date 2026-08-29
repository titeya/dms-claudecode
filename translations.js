.pragma library

var strings = {
    "Claude Code Usage":
        { fr: "Utilisation Claude Code", es: "Uso de Claude Code" },
    "Subscription":
        { fr: "Abonnement", es: "Suscripción" },
    "Live check failed — showing cached data":
        { fr: "Échec de la vérification en direct — affichage des données en cache", es: "Fallo la verificación en vivo — mostrando datos en caché" },
    "5h Rate Window":
        { fr: "Fenêtre de 5 h", es: "Ventana de 5 h" },
    "used":
        { fr: "utilisé", es: "usado" },
    "Resets in":
        { fr: "Réinitialisation dans", es: "Restablecimiento en" },
    "Resetting...":
        { fr: "Réinitialisation...", es: "Restableciendo..." },
    "7-Day Usage":
        { fr: "Utilisation sur 7 jours", es: "Uso durante 7 días" },
    "sessions":
        { fr: "sessions", es: "sesiones" },
    "msgs":
        { fr: "messages", es: "mensajes" },
    "Daily Activity":
        { fr: "Activité quotidienne", es: "Actividad diaria" },
    "Token Consumption":
        { fr: "Consommation de tokens", es: "Consumo de tokens" },
    "Today":
        { fr: "Aujourd'hui", es: "Hoy" },
    "Week":
        { fr: "Semaine", es: "Semana" },
    "Month":
        { fr: "Mois", es: "Mes" },
    "Models This Week":
        { fr: "Modèles cette semaine", es: "Modelos esta semana" },
    "Since":
        { fr: "Depuis", es: "Desde" },
    "Max":
        { fr: "Max", es: "Max" },
    "Pro":
        { fr: "Pro", es: "Pro" },
    "Free":
        { fr: "Gratuit", es: "Gratis" },
    "Team":
        { fr: "Équipe", es: "Equipo" },
    "Enterprise":
        { fr: "Entreprise", es: "Empresa" },
    // Settings
    "Monitor your Claude Code subscription usage. Rate limits and subscription tier are detected automatically via the Anthropic API.":
        {
            fr: "Surveillez l'utilisation de votre abonnement Claude Code. Les limites d'utilisation et le type d'abonnement sont détectés automatiquement via l'API Anthropic.",
            es: "Supervisa el uso de tu suscripción a Claude Code. Los límites de uso y el tipo de suscripción se detectan automáticamente mediante la API de Anthropic."
        },
    "Refresh Interval":
        { fr: "Intervalle de rafraîchissement", es: "Intervalo de actualización" },
    "How often to fetch usage data (minutes)":
        { fr: "Fréquence de mise à jour des données (minutes)", es: "Frecuencia de actualización de los datos (minutos)" },
    "All":
        { fr: "Tout", es: "Todos" },
    "Profile":
        { fr: "Profil", es: "Perfil" },
    "total":
        { fr: "total", es: "total" },
    // Pacing
    "over pace":
        { fr: "au-dessus du rythme", es: "por encima del ritmo" },
    "under pace":
        { fr: "en dessous du rythme", es: "por debajo del ritmo" },
    "On pace":
        { fr: "Dans les temps", es: "Al ritmo previsto" },
    "Over quota":
        { fr: "Quota dépassé", es: "Cuota superada" },
    "Show pacing":
        { fr: "Afficher le rythme", es: "Mostrar el ritmo de consumo" },
    "Show whether usage is ahead of or behind the time window":
        {
            fr: "Indique si l'utilisation est en avance ou en retard sur la fenêtre de temps",
            es: "Indica si el consumo está adelantado o retrasado respecto a la ventana de tiempo"
        },
    "Custom Profiles":
        { fr: "Profils personnalisés", es: "Perfiles personalizados" },
    "Name":
        { fr: "Nom", es: "Nombre" },
    "Config directory":
        { fr: "Dossier de configuration", es: "Directorio de configuración" },
    "Track extra Claude config directories. Point at a CLAUDE_CONFIG_DIR (the folder containing projects/). ~/.claude, Claude Code Switcher and claude-code-profiles are detected automatically.":
        {
            fr: "Suivez d'autres dossiers de configuration Claude. Indiquez un CLAUDE_CONFIG_DIR (le dossier contenant projects/). ~/.claude, Claude Code Switcher et claude-code-profiles sont détectés automatiquement.",
            es: "Haz seguimiento de otros directorios de configuración de Claude. Indica un CLAUDE_CONFIG_DIR (la carpeta que contiene projects/). ~/.claude, Claude Code Switcher y claude-code-profiles se detectan automáticamente."
        },
    "Add":
        { fr: "Ajouter", es: "Añadir" },
    "Remove":
        { fr: "Supprimer", es: "Eliminar" },
    "No items added yet":
        { fr: "Aucun élément ajouté pour le moment", es: "Todavía no se ha añadido ningún elemento" },
}

function tr(key, lang) {
    if (!lang || lang === "en" || !strings[key] || !strings[key][lang])
        return key
    return strings[key][lang]
}
