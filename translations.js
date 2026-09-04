.pragma library

var strings = {
    "AI Usage":
        { fr: "Utilisation de l'IA", es: "Uso de IA" },
    "Claude":
        { fr: "Claude", es: "Claude" },
    "ChatGPT":
        { fr: "ChatGPT", es: "ChatGPT" },
    "Plan":
        { fr: "Forfait", es: "Plan" },
    "Primary Window":
        { fr: "Fenêtre principale", es: "Ventana principal" },
    "Secondary Window":
        { fr: "Fenêtre secondaire", es: "Ventana secundaria" },
    "5h Window":
        { fr: "Fenêtre de 5 h", es: "Ventana de 5 h" },
    "Weekly Window":
        { fr: "Fenêtre hebdomadaire", es: "Ventana semanal" },
    "Window":
        { fr: "Fenêtre", es: "Ventana" },
    "Claude Code Usage":
        { fr: "Utilisation Claude Code", es: "Uso de Claude Code" },
    "Subscription":
        { fr: "Abonnement", es: "Suscripción" },
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
    "This Week":
        { fr: "Cette semaine", es: "Esta semana" },
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
    "Enable Claude Source":
        { fr: "Activer la source Claude", es: "Activar la fuente Claude" },
    "Show Claude Code usage. Off, or Claude Code not installed, hides its ring entirely.":
        {
            fr: "Affiche l'utilisation de Claude Code. Désactivé, ou si Claude Code n'est pas installé, masque entièrement son anneau.",
            es: "Muestra el uso de Claude Code. Si está desactivado, o Claude Code no está instalado, oculta completamente su anillo."
        },
    "Enable ChatGPT Source":
        { fr: "Activer la source ChatGPT", es: "Activar la fuente ChatGPT" },
    "Show Codex/ChatGPT usage. Off, or Codex not installed, hides its ring entirely.":
        {
            fr: "Affiche l'utilisation de Codex/ChatGPT. Désactivé, ou si Codex n'est pas installé, masque entièrement son anneau.",
            es: "Muestra el uso de Codex/ChatGPT. Si está desactivado, o Codex no está instalado, oculta completamente su anillo."
        },
    "Custom Profiles":
        { fr: "Profils personnalisés", es: "Perfiles personalizados" },
    "Custom ChatGPT Accounts":
        { fr: "Comptes ChatGPT personnalisés", es: "Cuentas de ChatGPT personalizadas" },
    "Track extra Codex accounts. Point at a CODEX_HOME (the folder containing auth.json). ~/.codex is detected automatically as \"default\".":
        {
            fr: "Suivez d'autres comptes Codex. Indiquez un CODEX_HOME (le dossier contenant auth.json). ~/.codex est détecté automatiquement comme « default ».",
            es: "Haz seguimiento de otras cuentas de Codex. Indica un CODEX_HOME (la carpeta que contiene auth.json). ~/.codex se detecta automáticamente como «default»."
        },
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
    // Login action
    "Not logged in":
        { fr: "Non connecté", es: "No has iniciado sesión" },
    "Session expired":
        { fr: "Session expirée", es: "Sesión caducada" },
    "Usage data unavailable until you log in.":
        {
            fr: "Données d'utilisation indisponibles tant que vous n'êtes pas connecté.",
            es: "Los datos de uso no estarán disponibles hasta que inicies sesión."
        },
    "Log in":
        { fr: "Se connecter", es: "Iniciar sesión" },
    "Logging in…":
        { fr: "Connexion en cours…", es: "Iniciando sesión…" },
}

function tr(key, lang) {
    if (!lang || lang === "en" || !strings[key] || !strings[key][lang])
        return key
    return strings[key][lang]
}
