#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#include <cstrike>

//#define USE_COLORS

#if defined USE_COLORS
#include <multicolors>
#endif

#define PL_VERSION "1.0.0"

#define CHAT_EXTRA_BYTES 255

#define BEAM_COLOR_TEAM {0, 0, 255, 255}
#define BEAM_COLOR_ENEMY {255, 0, 0, 255}

//#define DEBUG

public Plugin myinfo = {
    name = "Who Did I Flash?",
    author = "Christian Deacon (Gamemann)",
    description = "Notifies players when they flash their teammates.",
    version = PL_VERSION,
    url = "https://ModdingCommunity.com"
};

// ConVars
ConVar gCvEnabled = null;
ConVar gCvMaxDistance = null;

ConVar gCvTeam = null;
ConVar gCvTeamAnnounceNames = null;

ConVar gCvEnemy = null;
ConVar gCvEnemyAnnounceNames = null;

ConVar gCvCreateBeam = null;
ConVar gCvBeamLife = null;
ConVar gCvBeamWidth = null;

// ConVar values
bool gEnabled;
float gMaxDistance;

bool gTeam;
bool gTeamAnnounceNames;

bool gEnemy;
bool gEnemyAnnounceNames;

bool gCreateBeam;
float gBeamLife;
float gBeamWidth;

// Cookies
Handle gCDisableTeam = null;
Handle gCDisableEnemy = null;

bool gDisableTeam[MAXPLAYERS+1];
bool gDisableEnemy[MAXPLAYERS+1];

public void OnPluginStart() {
    // ConVars.
    gCvEnabled = CreateConVar("wdif_enabled", "1", "Whether to enable the Who Did I Flash plugin.", _, true, 0.0, true, 1.0);
    HookConVarChange(gCvEnabled, CVar_Changed);

    gCvMaxDistance = CreateConVar("wdif_max_distance", "6000.0", "The maximum distance from the flash detonation to check users.", _, true, 0.0);
    HookConVarChange(gCvMaxDistance, CVar_Changed);

    gCvTeam = CreateConVar("wdif_team", "1", "Notify flashbang thrower of teammates they've flashed", _, true, 0.0, true, 1.0);
    HookConVarChange(gCvTeam, CVar_Changed);

    gCvTeamAnnounceNames = CreateConVar("wdif_team_announce_names", "1", "Announce teammate names.", _, true, 0.0, true, 1.0);
    HookConVarChange(gCvTeamAnnounceNames, CVar_Changed);

    gCvEnemy = CreateConVar("wdif_enemy", "1", "Notify flashbang thrower of enemies they've flashed.", _, true, 0.0, true, 1.0);
    HookConVarChange(gCvEnemy, CVar_Changed);

    gCvEnemyAnnounceNames = CreateConVar("wdif_enemy_announce_names", "1", "Announce enemy names.", _, true, 0.0, true, 1.0);
    HookConVarChange(gCvEnemyAnnounceNames, CVar_Changed);

    gCvCreateBeam = CreateConVar("wdif_create_beam", "0", "If 1, creates a temporary beam. Used for debugging", _, true, 0.0, true, 1.0);
    HookConVarChange(gCvCreateBeam, CVar_Changed);

    gCvBeamLife = CreateConVar("wdif_beam_life", "5.0", "The beam lifetime in seconds.");
    HookConVarChange(gCvBeamLife, CVar_Changed);

    gCvBeamWidth = CreateConVar("wdif_beam_width", "2.0", "The beam width.");
    HookConVarChange(gCvBeamWidth, CVar_Changed);

    CreateConVar("wdif_version", PL_VERSION, "The Who Did I Flash plugin's version.");

    // Events.
    HookEvent("flashbang_detonate", Event_FlashbangDetonate);

    // Load translations.
    LoadTranslations("wdif.phrases.txt");

    // Load config,
    AutoExecConfig(true, "plugin.wdif");

    // Commands.
    RegConsoleCmd("sm_wdif", Command_WDIF, "The WDIF menu.");

    // Load cookies.
    gCDisableTeam = RegClientCookie("wdif_disable_team", "Disables WDIF team notifications.", CookieAccess_Public);
    gCDisableEnemy = RegClientCookie("wdif_disable_enemy", "Disables WDIF enemy notifications.", CookieAccess_Public);

    // Cookie late loading.
    for (int i = 1; i <= MaxClients; i++) {
        if (!AreClientCookiesCached(i))
            continue;

        OnClientCookiesCached(i);
    }
}

void SetCVars() {
    gEnabled = GetConVarBool(gCvEnabled);
    gMaxDistance = GetConVarFloat(gCvMaxDistance);

    gTeam = GetConVarBool(gCvTeam);
    gTeamAnnounceNames = GetConVarBool(gCvTeamAnnounceNames);

    gEnemy = GetConVarBool(gCvEnemy);
    gEnemyAnnounceNames = GetConVarBool(gCvEnemyAnnounceNames);

    gCreateBeam = GetConVarBool(gCvCreateBeam);
    gBeamLife = GetConVarFloat(gCvBeamLife);
    gBeamWidth = GetConVarFloat(gCvBeamWidth);
}

public void OnConfigsExecuted() {
    SetCVars();
}

public void CVar_Changed(Handle cv, const char[] oldV, const char[] newV) {
    SetCVars();
}

void BPrintToChat(int client, const char[] msg, any...) {
    // We need to format the message.
    int len = strlen(msg) + CHAT_EXTRA_BYTES;
    char[] fMsg = new char[len];

    VFormat(fMsg, len, msg, 3);

#if defined USE_COLORS
    CPrintToChat(client, fMsg);
#else
    PrintToChat(client, fMsg);
#endif
}

public void OnClientCookiesCached(int client) {
    char val[8];

    // Check disable team.
    GetClientCookie(client, gCDisableTeam, val, sizeof(val));

    gDisableTeam[client] = val[0] != '\0' && StringToInt(val) > 0;

    // Check disable enemy.
    GetClientCookie(client, gCDisableEnemy, val, sizeof(val));

    gDisableEnemy[client] = val[0] != '\0' && StringToInt(val) > 0;
}

public int WDIFMenuHandler(Menu m, MenuAction action, int client, int param2) {
    switch (action) {
        case MenuAction_Select: {
            // Get item info.
            char buffer[MAX_NAME_LENGTH];
            m.GetItem(param2, buffer, sizeof(buffer));

            // Check for team.
            if(strcmp(buffer, "team", false) == 0) {
                if (gDisableTeam[client]) {
                    gDisableTeam[client] = false;
                    SetClientCookie(client, gCDisableTeam, "0");
                } else {
                    gDisableTeam[client] = true;
                    SetClientCookie(client, gCDisableTeam, "1");
                }
            } else if (strcmp(buffer, "enemy", false) == 0) {
                if (gDisableEnemy[client]) {
                    gDisableEnemy[client] = false;
                    SetClientCookie(client, gCDisableEnemy, "0");
                } else {
                    gDisableEnemy[client] = true;
                    SetClientCookie(client, gCDisableEnemy, "1");
                }
            }

            // Rebuild menu.
            BuildWDIFMenu(client);

            return 0;
        }

        case MenuAction_End: {
            delete m;
        }
    }
    return 0;
}

void BuildWDIFMenu(int client) {
    // We'll want to build a menu.
    Menu m = new Menu(WDIFMenuHandler);

    // Set menu title.
    m.SetTitle("%T", "MenuTitle", LANG_SERVER);

    char buffer[255];

    // Format team choice.
    if (gDisableTeam[client])
        Format(buffer, sizeof(buffer), "%t", "MenuEnableTeam");
    else
        Format(buffer, sizeof(buffer), "%t", "MenuDisableTeam");

    m.AddItem("team", buffer);

    // Format enemy choice.
    if (gDisableEnemy[client])
        Format(buffer, sizeof(buffer), "%t", "MenuEnableEnemy");
    else
        Format(buffer, sizeof(buffer), "%t", "MenuDisableEnemy");

    m.AddItem("enemy", buffer);

    // Include exit button.
    m.ExitButton = true;

    // Display menu to client.
    m.Display(client, -1);
}

public Action Command_WDIF(int client, int args) {
    BuildWDIFMenu(client);

    return Plugin_Handled;
}

public Action Event_FlashbangDetonate(Event ev, const char[] name, bool dontBroadcast) {
    // Check if we're enabled.
    if (!gEnabled)
        return Plugin_Continue;

    // Get thrower ID.
    int thrower = GetClientOfUserId(ev.GetInt("userid"));

    // Check thrower.
    if (!IsClientInGame(thrower))
        return Plugin_Continue;

    // If notifications are disabled entirely, just ignore.
    if (gDisableTeam[thrower] && gDisableEnemy[thrower])
        return Plugin_Continue;

    // Get thrower team.
    int team = GetClientTeam(thrower);

    // Get flashbang detonation origin.
    float fbOrigin[3];
    fbOrigin[0] = ev.GetFloat("x");
    fbOrigin[1] = ev.GetFloat("y");
    fbOrigin[2] = ev.GetFloat("z");

    int flashedEnemy = 0;
    int flashedTeam = 0;

#if defined DEBUG
    int flashedTotal = 0;
#endif

    for (int i = 1; i <= MaxClients; i++) {
        // Make sure client is valid.
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || i == thrower)
            continue;

        int plTeam = GetClientTeam(i);

        // Check team.
        if (plTeam == team && (!gTeam || gDisableTeam[thrower]))
            continue;

        if (plTeam != team && (!gEnemy | gDisableEnemy[thrower]))
            continue;

        // Get player origin.
        float plOrigin[3];
        GetClientEyePosition(i, plOrigin);

        // Create beam if needed.
        if (gCreateBeam) {
            int color[4];

            if (plTeam == team)
                color = BEAM_COLOR_TEAM;
            else
                color = BEAM_COLOR_ENEMY;

            TE_SetupBeamPoints(fbOrigin, plOrigin, PrecacheModel("materials/sprites/laserbeam.vmt"), 0, 0, 0, gBeamLife, gBeamWidth, gBeamWidth, 1, 0.0, color, 0);
            TE_SendToAll();
        }

        // Make sure client is within distance of flashbang.
        if (GetVectorDistance(fbOrigin, plOrigin) > gMaxDistance)
            continue;

        // Get flash duration.
        float flashDuration = GetEntPropFloat(i, Prop_Send, "m_flFlashDuration");

        if (flashDuration <= 0.0)
            continue;

#if defined DEBUG
        flashedTotal++;
#endif
        
        // Create a trace ray and check if we've hit an entity or world.
        Handle trace = TR_TraceRayFilterEx(fbOrigin, plOrigin, MASK_SOLID, RayType_EndPoint, TraceFilter, i);

        if (TR_DidHit(trace)) {
            delete trace;

            continue;
        }

        // Increment flashed count.
        if (plTeam == team)
            flashedTeam++;
        else
            flashedEnemy++;

        // Check for individual announce.
        if ((gTeamAnnounceNames && plTeam == team) || (gEnemyAnnounceNames && plTeam != team)) {
            // Get user name who was flashed.
            char flashedName[MAX_NAME_LENGTH];
            GetClientName(i, flashedName, sizeof(flashedName));

            // Print to throwers chat.
            if (plTeam == team)
                BPrintToChat(thrower, "%t %t", "Tag", "ClAnnounceTeam", flashedName, flashDuration);
            else
                BPrintToChat(thrower, "%t %t", "Tag", "ClAnnounceEnemy", flashedName, flashDuration);
        }
        
        // Delete trace handle.
        delete trace;
    }

    // Print to chat if we flashed teammates.
    if (flashedTeam > 0 || flashedEnemy > 0)
        BPrintToChat(thrower, "%t %t", "Tag", "Announce", flashedTeam, flashedEnemy);

#if defined DEBUG
        BPrintToChat(thrower, "%t Total number of users who are flashed: %d", "Tag", flashedTotal);
#endif

    return Plugin_Continue;
}

public bool TraceFilter(int entity, int contentsMask, int client) {
    if (entity > 0 && entity <= MaxClients)
        return false;

    // Ignore flashbang projectile.
    char className[MAX_NAME_LENGTH];

    if (IsValidEntity(entity))
        GetEntityClassname(entity, className, sizeof(className));

    if (strcmp(className, "flashbang_projectile", false) == 0)
        return false;

    return true;
}