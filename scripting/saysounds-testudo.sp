#include <sourcemod>
#include <sdktools>
#include <clientprefs>

// Cat: More colors
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma semicolon 1

#define PLUGIN_VERSION "1.4_cat"

#define SAYSOUND_FLAG_ADMIN		(1 << 0)
#define SAYSOUND_FLAG_DOWNLOAD		(1 << 1)
#define SAYSOUND_FLAG_CUSTOMVOLUME	(1 << 2)
#define SAYSOUND_FLAG_CUSTOMLENGTH	(1 << 3)

// Cat: Faction sounds
#define SAYSOUND_FLAG_FACTION		(1 << 4)

// Cat: Music flag
#define SAYSOUND_FLAG_MUSIC		(1 << 5)

#define SAYSOUND_TRIGGER_SIZE 64

// Cat: PVKII Teams
enum
{
	TEAM_UNASSIGNED = 0,
	TEAM_SPECTATOR,
	TEAM_PIRATES,
	TEAM_VIKINGS,
	TEAM_KNIGHTS,

	PVK2_TEAMS_COUNT
}

new bool:gb_lamesoundengine;

enum
{
	SAYSOUND_CLIENT = 0,
	SAYSOUND_DONOR,
	SAYSOUND_ADMIN
}
new g_access[MAXPLAYERS+1];

enum
{
	SAYSOUND_PREF_DISABLED = 0,
	SAYSOUND_PREF_BANNED
}
new g_clientprefs[MAXPLAYERS+1][3];

new g_serial;
new g_soundcount[MAXPLAYERS+1];
new Float:gf_LastSaysound[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "Say Sounds (Redux)",
	author = "Friagram",
	description = "Plays sound files",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/groups/poniponiponi"
};

new Handle:gh_flags, Handle:gh_trigger, Handle:gh_paths, Handle:gh_length, Handle:gh_volume, Handle:gh_recentsounds;
new Handle:gh_cookie;
new Handle:gh_menu, Handle:gh_adminmenu;
new Handle:hAdminMenu = INVALID_HANDLE;

// Cat: Faction sounds
new Handle:gh_factionsounds[PVK2_TEAMS_COUNT];

new bool:gb_enabled;
new g_saysound_limit[3];
new Float:gf_saysound_delay[3];

// Cat: Music flag
new Float:gf_saysound_music_delay[3];
new bool:gb_preventspam[3];
new bool:gb_saysound_round;
new bool:gb_saysound_sentence;
new bool:gb_saysound_blocktrigger;
new g_saysound_excludecount;
new bool:gb_playingame;
new Float:gf_saysound_volume;

// Cat: More colors needs this
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    MarkNativeAsOptional("GetUserMessageType");
    return APLRes_Success;
}

public OnPluginStart()
{
	switch(GetEngineVersion())
	{
		case Engine_CSGO, Engine_DOTA: gb_lamesoundengine = true;
	}

	// ***Load Translations **
	LoadTranslations("common.phrases");

	CreateConVar("sm_saysounds_redux_version", PLUGIN_VERSION, "Say Sounds Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	decl Handle:cvar;
	HookConVarChange(cvar = CreateConVar("sm_saysounds_enable","1","Turns Sounds On/Off", FCVAR_PLUGIN, true, 0.0, true, 1.0), Cvar_EnableChanged);
	gb_enabled = GetConVarBool(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_sound_limit","10","Maximum sounds per person (0 for unlimited)", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_LimitChanged);
	g_saysound_limit[0] = GetConVarInt(cvar);
	
	HookConVarChange(cvar = CreateConVar("sm_saysounds_donor_limit","15","Maximum sounds for saysounds_donor (0 for unlimited)", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_DonorLimitChanged);
	g_saysound_limit[1] = GetConVarInt(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_admin_limit","0","Maximum sounds per saysounds_admin (0 for unlimited)", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_AdminLimitChanged);
	g_saysound_limit[2] = GetConVarInt(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_sound_delay","5.0","Time between each sound trigger, 0.0 to disable checking", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_DelayChanged);
	gf_saysound_delay[0] = GetConVarFloat(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_donor_delay","3.0","User flags to bypass the Time between sounds check", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_DonorDelayChanged);
	gf_saysound_delay[1] = GetConVarFloat(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_admin_delay","1.0","User flags to bypass the Time between sounds check", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_AdminDelayChanged);
	gf_saysound_delay[2] = GetConVarFloat(cvar);
	
	// Cat: Music flag
	HookConVarChange(cvar = CreateConVar("sm_saysounds_music_delay","5.0","Time between each sound trigger, 0.0 to disable checking", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_MusicDelayChanged);
	gf_saysound_music_delay[0] = GetConVarFloat(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_music_delay_donor","3.0","User flags to bypass the Time between music check", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_MusicDelayDonorChanged);
	gf_saysound_music_delay[1] = GetConVarFloat(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_music_delay_admin","1.0","User flags to bypass the Time between music check", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_MusicDelayAdminChanged);
	gf_saysound_music_delay[2] = GetConVarFloat(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_round", "0", "If set, sm_saysoundhe_sound_limit is the limit per round instead of per map", FCVAR_PLUGIN, true, 0.0, true, 1.0), Cvar_RoundChanged);
	gb_saysound_round = GetConVarBool(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_sound_sentence", "1", "When set, will trigger sounds if keyword is embedded in a sentence", FCVAR_PLUGIN, true, 0.0, true, 1.0), Cvar_SentenceChanged);
	gb_saysound_sentence = GetConVarBool(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_block_trigger", "0", "If set, block the sound trigger to be displayed in the chat window", FCVAR_PLUGIN, true, 0.0, true, 1.0), Cvar_BlockTriggerChanged);
	gb_saysound_blocktrigger = GetConVarBool(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_exclude", "2", "Number of sounds that must be different before this sound can be replayed", FCVAR_PLUGIN, true, 0.0, false, 0.0), Cvar_ExcludeChanged);
	g_saysound_excludecount = GetConVarInt(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_exclude_client", "1", "If set, clients obey exclude count", FCVAR_PLUGIN, true, 0.0, true, 1.0), Cvar_SpamClientChanged);
	gb_preventspam[0] = GetConVarBool(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_exclude_donor", "1", "If set, donors obey exclude count", FCVAR_PLUGIN, true, 0.0, true, 1.0), Cvar_SpamDonorChanged);
	gb_preventspam[1] = GetConVarBool(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_exclude_admin", "0", "If set, admins obey exclude count", FCVAR_PLUGIN, true, 0.0, true, 1.0), Cvar_SpamAdminChanged);
	gb_preventspam[2] = GetConVarBool(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_playingame","0.0","Play as an emit sound or direct (0 / 1)",FCVAR_PLUGIN,true,0.0,true,1.0), Cvar_PlayIngameChanged);
	gb_playingame = GetConVarBool(cvar);

	HookConVarChange(cvar = CreateConVar("sm_saysounds_volume","1.0","Volume setting for Say Sounds (0.0 <= x <= 1.0)",FCVAR_PLUGIN,true,0.0,true,1.0), Cvar_VolumeChanged);
	gf_saysound_volume = GetConVarFloat(cvar);

	gh_cookie = RegClientCookie("saysounds_pref", "saysounds data", CookieAccess_Protected);
	SetCookieMenuItem(SaysoundClientPref, 0, "Say Sounds Settings");

	RegAdminCmd("sm_sound_ban", Command_Sound_Ban, ADMFLAG_BAN, "sm_sound_ban <user> : Bans a player from using sounds");
	RegAdminCmd("sm_sound_reset", Command_Sound_Reset, ADMFLAG_GENERIC, "sm_sound_reset <user | all> : Resets sound quota for user, or everyone if all");
	RegConsoleCmd("sm_soundlist", Command_Sound_Menu, "Display a menu sounds to play");
	RegConsoleCmd("sm_sounds", Command_Sound_Toggle, "Toggle Saysounds");

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say2");
	AddCommandListener(Command_Say, "say_team");

	// Cat: Doesn't work in PVKII
	//HookEvent("teamplay_round_start", Event_RoundStart);

	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(topmenu);
	}

	PrepareSounds();
	
	for(new client = 1; client <= MaxClients; client++)
	{
		if(IsClientConnected(client) && IsClientAuthorized(client) && !IsFakeClient(client))
		{
			OnClientPostAdminCheck(client);
			if(AreClientCookiesCached(client))
			{
				OnClientCookiesCached(client);
			}
		}
	}
}

public Cvar_EnableChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gb_enabled = bool:StringToInt(newValue);
}
public Cvar_LimitChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_saysound_limit[0] = StringToInt(newValue);
}
public Cvar_DonorLimitChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_saysound_limit[1] = StringToInt(newValue);
}
public Cvar_AdminLimitChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_saysound_limit[2] = StringToInt(newValue);
}
public Cvar_DelayChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gf_saysound_delay[0] = StringToFloat(newValue);
}
public Cvar_DonorDelayChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gf_saysound_delay[1] = StringToFloat(newValue);
}
public Cvar_AdminDelayChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gf_saysound_delay[2] = StringToFloat(newValue);
}

// Cat: Music flag
public Cvar_MusicDelayChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gf_saysound_music_delay[0] = StringToFloat(newValue);
}
public Cvar_MusicDelayDonorChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gf_saysound_music_delay[1] = StringToFloat(newValue);
}
public Cvar_MusicDelayAdminChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gf_saysound_music_delay[2] = StringToFloat(newValue);
}
public Cvar_RoundChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gb_saysound_round = bool:StringToInt(newValue);
}
public Cvar_SentenceChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gb_saysound_sentence = bool:StringToInt(newValue);
}
public Cvar_BlockTriggerChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gb_saysound_blocktrigger = bool:StringToInt(newValue);
}
public Cvar_ExcludeChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_saysound_excludecount = StringToInt(newValue);
	ClearArray(gh_recentsounds);
}
public Cvar_SpamClientChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gb_preventspam[0] = bool:StringToInt(newValue);
}
public Cvar_SpamDonorChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gb_preventspam[1] = bool:StringToInt(newValue);
}
public Cvar_SpamAdminChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gb_preventspam[2] = bool:StringToInt(newValue);
}

public Cvar_PlayIngameChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gb_playingame = bool:StringToInt(newValue);
	if(gb_playingame)
	{
		PrecacheSounds();
	}
}
public Cvar_VolumeChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	gf_saysound_volume = StringToFloat(newValue);
}

public OnClientCookiesCached(client)
{
	if(!IsFakeClient(client))
	{
		decl String:cookie[32];
		new String:segment[4][4];
		GetClientCookie(client, gh_cookie, cookie, sizeof(cookie));
		ExplodeString(cookie, ";", segment, 4, 4);

		g_clientprefs[client][SAYSOUND_PREF_DISABLED] = bool:StringToInt(segment[0]);
		g_clientprefs[client][SAYSOUND_PREF_BANNED] = bool:StringToInt(segment[1]);

		if(StringToInt(segment[2]) == g_serial)
		{
			g_soundcount[client] = StringToInt(segment[3]);
		}
		else
		{
			g_soundcount[client] = 0;
		}
	}
}

public OnClientDisconnect(client)
{
	if(!IsFakeClient(client))
	{
		StoreClientCookies(client);
	}
}

StoreClientCookies(client)
{
	if(AreClientCookiesCached(client))
	{
		decl String:cookie[32];
		FormatEx(cookie, sizeof(cookie), "%d;%d;%d;%d",
			g_clientprefs[client][SAYSOUND_PREF_DISABLED], g_clientprefs[client][SAYSOUND_PREF_BANNED],
			g_serial, g_soundcount[client]);

		SetClientCookie(client, gh_cookie, cookie);
	}
}

public OnMapStart()
{
	ResetClients();

	PrecacheSounds();
}

ResetClients()
{
	g_serial++;
	ClearArray(gh_recentsounds);
	if (gb_saysound_round)
	{
		for (new client = 1; client <= MaxClients; client++)
		{
			g_soundcount[client] = 0;
		}
	}
}

PrecacheSounds()
{
	decl String:soundfile[PLATFORM_MAX_PATH];
	decl String:buffer[PLATFORM_MAX_PATH];
	decl Handle:hpath;
	decl flags;
	
	for(new i = GetArraySize(gh_paths) - 1; i >= 0; i--)
	{
		hpath = GetArrayCell(gh_paths, i);
		flags = GetArrayCell(gh_flags, i);

		for(new k = GetArraySize(hpath) - 1; k >= 0; k--)
		{
			GetArrayString(hpath, k, soundfile, sizeof(soundfile));
			if(gb_playingame)
			{
				if(gb_lamesoundengine)
				{
					AddToStringTable(FindStringTable( "soundprecache" ), soundfile);
				}
				else
				{
					PrecacheSound(soundfile, true);
				}
			}

			if(flags & SAYSOUND_FLAG_DOWNLOAD)
			{
				FormatEx(buffer, sizeof(buffer), "sound/%s", soundfile);
				AddFileToDownloadsTable(buffer);
			}
		}
	}
	
	// Cat: Faction sounds
	for (new team = TEAM_PIRATES; team < TEAM_KNIGHTS+1; team++)
	{
		decl Handle:hSounds;
		hSounds = gh_factionsounds[team];
		
		for(new i = GetArraySize(hSounds) - 1; i >= 0; i--)
		{
			hpath = GetArrayCell(hSounds, i);

			for(new k = GetArraySize(hpath) - 1; k >= 0; k--)
			{
				GetArrayString(hpath, k, soundfile, sizeof(soundfile));
				
				if (soundfile[0] == '\0')
					continue;
				
				if(gb_playingame)
				{
					if(gb_lamesoundengine)
					{
						AddToStringTable(FindStringTable( "soundprecache" ), soundfile);
					}
					else
					{
						PrecacheSound(soundfile, true);
					}
				}

				if(flags & SAYSOUND_FLAG_DOWNLOAD)
				{
					FormatEx(buffer, sizeof(buffer), "sound/%s", soundfile);
					AddFileToDownloadsTable(buffer);
				}
			}
		}
	}
}

PrepareSounds()
{
	gh_flags = CreateArray();
	gh_trigger = CreateArray(ByteCountToCells(SAYSOUND_TRIGGER_SIZE));
	gh_paths = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
	gh_length = CreateArray();
	gh_volume = CreateArray();
	gh_recentsounds = CreateArray();
	
	// Cat: Faction sounds
	for (new i = 0; i < PVK2_TEAMS_COUNT; i++)
		gh_factionsounds[i] = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

	decl String:soundlistfile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM,soundlistfile,sizeof(soundlistfile),"configs/saysounds.cfg");
	if(!FileExists(soundlistfile))
	{
		SetFailState("saysounds.cfg not parsed...file doesnt exist!");
	}
	else
	{
		new Handle:listfile = CreateKeyValues("soundlist");
		FileToKeyValues(listfile,soundlistfile);
		KvRewind(listfile);
		if (KvGotoFirstSubKey(listfile))
		{
			gh_menu = CreateMenu(menu_handler);
			gh_adminmenu = CreateMenu(menu_handler);
			
			SetMenuTitle(gh_menu, "Saysounds\n ");
			SetMenuTitle(gh_adminmenu, "Saysounds\n ");
		
			decl String:filelocation[PLATFORM_MAX_PATH], String:item[8], String:trigger[SAYSOUND_TRIGGER_SIZE];
			decl Handle:soundpath;
			decl flags;
			decl Float:duration, Float:volume;
			
			// Cat: Faction sounds
			decl Handle:pirateSounds;
			decl Handle:vikingSounds;
			decl Handle:knightSounds;
			decl Handle:spectatorSounds;

			do
			{
				KvGetString(listfile, "file", filelocation, sizeof(filelocation), "");
				if(filelocation[0] != '\0')
				{
					soundpath = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
					KvGetSectionName(listfile, trigger, sizeof(trigger));

					flags = 0;
					if(KvGetNum(listfile, "admin", 0))
					{
						flags |= SAYSOUND_FLAG_ADMIN;
						
						AddMenuItem(gh_adminmenu, trigger, trigger);
					}
					else
					{
						AddMenuItem(gh_adminmenu, trigger, trigger);
						AddMenuItem(gh_menu, trigger, trigger);
					}

					if(KvGetNum(listfile, "download", 1))
					{
						flags |= SAYSOUND_FLAG_DOWNLOAD;
					}

					duration = KvGetFloat(listfile, "duration", 0.0);
					if(duration)
					{
						flags |= SAYSOUND_FLAG_CUSTOMLENGTH;
					}

					volume = KvGetFloat(listfile, "volume", 0.0);
					if(volume)
					{
						flags |= SAYSOUND_FLAG_CUSTOMVOLUME;
						if(volume > 2.0)
						{
							volume = 2.0;
						}
					}
					
					// Cat: Faction sounds
					if(KvGetNum(listfile, "faction", 0))
					{
						flags |= SAYSOUND_FLAG_FACTION;
					}

					PushArrayCell(gh_paths, soundpath);
					PushArrayString(gh_trigger, trigger);
					PushArrayCell(gh_length, duration);
					PushArrayCell(gh_volume, volume);
					PushArrayCell(gh_flags, flags);
					
					if(gb_lamesoundengine)
					{
						Format(filelocation, sizeof(filelocation), "*%s", filelocation);	// prefix asterisk for newer games
					}

					PushArrayString(soundpath, filelocation);

					for (new i = 2;; i++)
					{
						FormatEx(item, sizeof(item),  "file%d", i);
						KvGetString(listfile, item, filelocation, sizeof(filelocation), "");
						if (filelocation[0] == '\0')
						{
							break;
						}
						PushArrayString(soundpath, filelocation);
					}
					
					// Cat: Faction sounds
					pirateSounds = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
					vikingSounds = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
					knightSounds = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
					spectatorSounds = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
					
					PushArrayCell(gh_factionsounds[TEAM_PIRATES], pirateSounds);
					PushArrayCell(gh_factionsounds[TEAM_VIKINGS], vikingSounds);
					PushArrayCell(gh_factionsounds[TEAM_KNIGHTS], knightSounds);
					PushArrayCell(gh_factionsounds[TEAM_SPECTATOR], spectatorSounds);
					PushArrayCell(gh_factionsounds[TEAM_UNASSIGNED], spectatorSounds);
					
					if (flags & SAYSOUND_FLAG_FACTION)
					{						
						decl String:pirateSound[PLATFORM_MAX_PATH];
						decl String:vikingSound[PLATFORM_MAX_PATH];
						decl String:knightSound[PLATFORM_MAX_PATH];
						decl String:spectatorSound[PLATFORM_MAX_PATH];
						
						KvGetString(listfile, "pirate", pirateSound, sizeof(pirateSound), "");
						KvGetString(listfile, "viking", vikingSound, sizeof(vikingSound), "");
						KvGetString(listfile, "knight", knightSound, sizeof(knightSound), "");
						KvGetString(listfile, "spectator", spectatorSound, sizeof(spectatorSound), "");
						
						PushArrayString(pirateSounds, pirateSound);
						PushArrayString(vikingSounds, vikingSound);
						PushArrayString(knightSounds, knightSound);
						PushArrayString(spectatorSounds, spectatorSound);
						
						for (new team = 0; team < PVK2_TEAMS_COUNT; team++)
						{
							for (new i = 2;; i++)
							{
								if (team == TEAM_PIRATES)
									FormatEx(item, sizeof(item),  "pirate%d", i);
								else if (team == TEAM_VIKINGS)
									FormatEx(item, sizeof(item),  "viking%d", i);
								else if (team == TEAM_KNIGHTS)
									FormatEx(item, sizeof(item),  "knight%d", i);
								else
									FormatEx(item, sizeof(item),  "spectator%d", i);
									
								KvGetString(listfile, item, filelocation, sizeof(filelocation), "");
								if (filelocation[0] == '\0')
								{
									break;
								}
								
								if (team == TEAM_PIRATES)
									PushArrayString(pirateSounds, filelocation);
								else if (team == TEAM_VIKINGS)
									PushArrayString(vikingSounds, filelocation);
								else if (team == TEAM_KNIGHTS)
									PushArrayString(knightSounds, filelocation);
								else
									PushArrayString(spectatorSounds, filelocation);
							}
						}
					}
					else
					{
						PushArrayString(pirateSounds, "");
						PushArrayString(vikingSounds, "");
						PushArrayString(knightSounds, "");
						PushArrayString(spectatorSounds, "");
					}
				}
			}
			while (KvGotoNextKey(listfile));
		}
		else
		{
			SetFailState("saysounds.cfg not parsed...No subkeys found!");
		}

		CloseHandle(listfile);
	}
}


public Action:Event_RoundStart(Handle:event,const String:name[],bool:dontBroadcast)
{
	ResetClients();

	return Plugin_Continue;
}

public OnClientPostAdminCheck(client)		// I'm not going to bother checking admin rehashing
{
	if(CheckCommandAccess(client, "saysounds_admin", ADMFLAG_CHAT, true))
	{
		g_access[client] = SAYSOUND_ADMIN;
	}
	else if(CheckCommandAccess(client, "saysounds_donor", ADMFLAG_RESERVATION, true))
	{
		g_access[client] = SAYSOUND_DONOR;
	}
	else
	{
		g_access[client] = SAYSOUND_CLIENT;
	}
}

public OnRebuildAdminCache(AdminCachePart:part)
{
    if(part == AdminCache_Admins)
    {
        CreateTimer(1.0, Timer_WaitForAdminCacheReload, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action:Timer_WaitForAdminCacheReload(Handle:timer)
{
    for(new client = 1; client <= MaxClients; client++)
    {
        if(IsClientConnected(client) && IsClientAuthorized(client) && !IsFakeClient(client))
        {
            OnClientPostAdminCheck(client);
        }
    }
}

public Action:Command_Say(client, const String:command[], argc)
{
	static String:speech[256];
	static startidx;

	if(gb_enabled && !g_clientprefs[client][SAYSOUND_PREF_DISABLED] && !g_clientprefs[client][SAYSOUND_PREF_BANNED])		// enabled, they can emit sounds to others
	{
		if (GetCmdArgString(speech, sizeof(speech)) >= 1)
		{
			startidx = 0;
			
			if (speech[strlen(speech)-1] == '"')
			{
				speech[strlen(speech)-1] = '\0';
				startidx = 1;
			}

			if (strcmp(command, "say2", false) == 0)
			{
				startidx += 4;
			}

			return  Action:AttemptSaySound(client, speech[startidx]);
		}
	}	
	return Plugin_Continue;
}

public Action:AttemptSaySound(client, String:sound[])
{
	static String:buffer[PLATFORM_MAX_PATH];
	
	// Cat: Buffer for trigger
	static String:trigger[PLATFORM_MAX_PATH];
	
	static size, flags;
	static Handle:hpath;
	
	// Cat: Faction sounds
	static Handle:hFactionPath;

	if(g_saysound_limit[g_access[client]])																			// is there a limit, are they at it
	{
		if(g_soundcount[client] >= g_saysound_limit[g_access[client]])
		{
			return Plugin_Continue;
		}
	}

	new Float:time = GetEngineTime();																							// are they experiencing delay
	if(time > gf_LastSaysound[client])
	{
		new bool:adminonly;

		size = GetArraySize(gh_paths);																				// traverse forward
		for(new i; i < size; i++)
		{
			GetArrayString(gh_trigger, i, trigger, sizeof(trigger));
			if((gb_saysound_sentence && StrContains(sound, trigger, false) >= 0) || strcmp(sound, trigger, false) == 0)
			{
				flags = GetArrayCell(gh_flags, i);
				if((flags & SAYSOUND_FLAG_ADMIN) && g_access[client] != SAYSOUND_ADMIN)
				{
					adminonly = true;

					continue;																					// perhaps there is something similar they can use
				}

				if(gb_preventspam[g_access[client]])
				{
					if(FindValueInArray(gh_recentsounds, i) != -1)
					{
						if(client && IsClientInGame(client))
						{
							PrintToChat(client, "[SM] this sound was recently played");
						}
						return Plugin_Continue;
					}
				}

				// Cat: Faction sounds
				if (flags & SAYSOUND_FLAG_FACTION)
				{
					hFactionPath = GetArrayCell(gh_factionsounds[GetClientTeam(client)], i);
					GetArrayString(hFactionPath, GetRandomInt(0, GetArraySize(hFactionPath)-1), buffer, sizeof(buffer));
				}
				else
				{
					hpath = GetArrayCell(gh_paths, i);
					GetArrayString(hpath, GetRandomInt(0, GetArraySize(hpath)-1), buffer, sizeof(buffer));
				}
				
				DoSaySound(client, buffer, trigger, (flags & SAYSOUND_FLAG_CUSTOMVOLUME) ? (Float:GetArrayCell(gh_volume, i)) : gf_saysound_volume);

				if(PushArrayCell(gh_recentsounds, i) >= g_saysound_excludecount)
				{
					RemoveFromArray(gh_recentsounds, 0);
				}

				if(gf_saysound_delay[g_access[client]])
				{
					if(flags & SAYSOUND_FLAG_CUSTOMLENGTH)
					{
						gf_LastSaysound[client] = time + Float:GetArrayCell(gh_length, i);
					}
					else if (flags & SAYSOUND_FLAG_MUSIC) // Cat: Music flag
					{
						gf_LastSaysound[client] = time + gf_saysound_music_delay[g_access[client]];
					}
					else
					{
						gf_LastSaysound[client] = time + gf_saysound_delay[g_access[client]];
					}
				}
				
				g_soundcount[client]++;
				DisplayRemainingSounds(client);
				
				if(gb_saysound_blocktrigger)
				{
					return Plugin_Handled;
				}

				return Plugin_Continue;
			}
		}
		
		if(adminonly)
		{
			if(client && IsClientInGame(client))
			{
				PrintToChat(client, "[SM] you do not have access to this sound");
			}
		}
	}

	return Plugin_Continue;
}

DisplayRemainingSounds(client)
{
	if(g_saysound_limit[g_access[client]])
	{
		if(client && IsClientInGame(client))
		{
			PrintToChat(client, "[SM] you have used %d/%d sounds", g_soundcount[client], g_saysound_limit[g_access[client]]);
		}
	}
}

// Cat: Add input for client and trigger
DoSaySound(client, String:soundfile[], String:trigger[], Float:volume)
{
	for(new target = 1; target<=MaxClients; target++)
	{
		if(IsClientInGame(target) && !g_clientprefs[target][SAYSOUND_PREF_DISABLED])
		{
			if(gb_playingame)
			{
				if(volume > 1.0)
				{
					volume *= 0.5;
					EmitSoundToClient(target, soundfile, .volume = volume);
					EmitSoundToClient(target, soundfile, .volume = volume);
				}
				else
				{
					EmitSoundToClient(target, soundfile, .volume = volume);
				}
			}
			else
			{
				if(volume >= 2.0)
				{
					ClientCommand(target, "playgamesound \"%s\";playgamesound \"%s\"", soundfile,soundfile);
				}
				else
				{
					ClientCommand(target, "playgamesound \"%s\"",soundfile);
				}
			}
		}
	}
	
	// Cat: Show message
	decl String:clientName[MAX_NAME_LENGTH];
	GetClientName(client, clientName, sizeof(clientName));
	
	if (GetClientTeam(client) == TEAM_PIRATES)
		CPrintToChatAll("{red}%s played sound \"%s\"", clientName, trigger);
	else if (GetClientTeam(client) == TEAM_VIKINGS)
		CPrintToChatAll("{lightgreen}%s played sound \"%s\"", clientName, trigger);
	else if (GetClientTeam(client) == TEAM_KNIGHTS)
		CPrintToChatAll("{blue}%s played sound \"%s\"", clientName, trigger);
	else
		PrintToChatAll("%s played sound \"%s\"", clientName, trigger);
}

public Action:Command_Sound_Reset(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[sm] usage: sm_sound_reset <target>");
		return Plugin_Handled;
	}

	new String:arg[64];
	GetCmdArg(1, arg, sizeof(arg));	

	decl String:name[64];
	new bool:isml,clients[MAXPLAYERS+1];
	new count=ProcessTargetString(arg,client,clients,MAXPLAYERS+1,COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_BOTS,name,sizeof(name),isml);
	if (count > 0)
	{
		for(new x=0;x<count;x++)
		{
			g_soundcount[clients[x]] = 0;
			DisplayRemainingSounds(clients[x]);
		}
	}
	else
	{
		ReplyToTargetError(client, count);
	}

	return Plugin_Handled;
}

public Action:Command_Sound_Ban(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[sm] usage: sm_sound_ban <target>");
		return Plugin_Handled;	
	}

	new String:arg[64];
	GetCmdArg(1, arg, sizeof(arg));	

	decl String:name[64];
	new bool:isml,clients[MAXPLAYERS+1];
	new count=ProcessTargetString(arg,client,clients,MAXPLAYERS+1,COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_NO_MULTI,name,sizeof(name),isml);
	if (count == 1)
	{
		g_clientprefs[clients[0]][SAYSOUND_PREF_BANNED] = !g_clientprefs[clients[0]][SAYSOUND_PREF_BANNED];
		ReplyToCommand(client, "[sm] %N ban status set to: %s", clients[0], g_clientprefs[clients[0]][SAYSOUND_PREF_BANNED] ? "banned" : "unbanned");
		
		StoreClientCookies(clients[0]);
	}
	else
	{
		ReplyToTargetError(client, count);
	}

	return Plugin_Handled;
}

public SaysoundClientPref(client, CookieMenuAction:action, any:info, String:buffer[], maxlen)
{
	if (action == CookieMenuAction_SelectOption)
	{
		ShowClientPrefMenu(client);
	}
}

ShowClientPrefMenu(client)
{
	new Handle:menu = CreateMenu(MenuHandlerClientPref);

	SetMenuTitle(menu, "Saysounds\n ");

	AddMenuItem(menu, "", g_clientprefs[client][SAYSOUND_PREF_DISABLED] ? "Saysounds: Disabled" : "Saysounds: Enabled");

	SetMenuExitButton(menu, true);

	DisplayMenu(menu, client, 0);
}

public MenuHandlerClientPref(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)	
	{
		if (param2 == 0)
		{
			g_clientprefs[param1][SAYSOUND_PREF_DISABLED] = !g_clientprefs[param1][SAYSOUND_PREF_DISABLED];
		}
		ShowClientPrefMenu(param1);
	} 
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public Action:Command_Sound_Toggle(client, args)
{
	if(client && IsClientInGame(client))
	{
		g_clientprefs[client][SAYSOUND_PREF_DISABLED]  = ! g_clientprefs[client][SAYSOUND_PREF_DISABLED];
		PrintToChat(client, "[SM] %s", g_clientprefs[client][SAYSOUND_PREF_DISABLED] ? "saysounds disabled" : "saysounds enabled");
	}

	return Plugin_Handled;
}

public Action:Command_Sound_Menu(client, args)
{
	if(client && IsClientInGame(client))
	{
		if(g_access[client] == SAYSOUND_ADMIN)
		{
			DisplayMenu(gh_adminmenu, client, 60);
		}
		else
		{
			DisplayMenu(gh_menu, client, 60);
		}
	}

	return Plugin_Handled;
}

public menu_handler(Handle:menu,MenuAction:action,client,selection)
{
	if(action==MenuAction_Select)
	{
		decl String:SelectionInfo[SAYSOUND_TRIGGER_SIZE];
		if (GetMenuItem(menu,selection,SelectionInfo,sizeof(SelectionInfo)))
		{
			if(gb_enabled && !g_clientprefs[client][SAYSOUND_PREF_DISABLED] && !g_clientprefs[client][SAYSOUND_PREF_BANNED])		// enabled, they can emit sounds to others
			{
				AttemptSaySound(client, SelectionInfo);
			}
		}
	}
}

public OnAdminMenuReady(Handle:topmenu)
{
	if (topmenu != hAdminMenu)
	{
		hAdminMenu = topmenu;
		new TopMenuObject:server_commands = FindTopMenuCategory(hAdminMenu, ADMINMENU_SERVERCOMMANDS);
		AddToTopMenu(hAdminMenu, "sm_soundlist", TopMenuObject_Item, Play_Admin_Sound, server_commands, "sm_soundlist", ADMFLAG_GENERIC);
	}
}

public Play_Admin_Sound(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Play A Saysound");
	}
	else if (action == TopMenuAction_SelectOption)
	{
		Command_Sound_Menu(param, 0);
	}
}

