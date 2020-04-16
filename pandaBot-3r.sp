#pragma semicolon 1

// *********************************************************************************
// INCLUDES
// *********************************************************************************

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include<tf2_stocks>

// *********************************************************************************
// DEFINES
// *********************************************************************************

// Plugin info
#define PLUGIN_NAME "Panda bot"
#define PLUGIN_AUTHOR "Panda Bear"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_CONTACT  "http://steamcommunity.com/id/flamingkirby/"

// Different distances to the CLIENT
#define ORBIT_DIST 450.0
#define CLOSE_DIST 700.0
#define NORM_DIST 1000.0
#define FAR_DIST 1500.0

// Converts radians to pi
#define PI 3.14159265359
#define RAD_TO_DEG (180.0 / PI)
#define DEG_TO_RAD (PI / 180.0)

//The max speed of the pyro
#define PYRO_SPEED 450.0

// The maximum number of rockets that can be handled
#define MAX_ROCKETS 100
#define MAX_ROCKET_CLASSES 50

#define ARRAY_END -100

// *********************************************************************************
// ENUMS
// *********************************************************************************

/*
* The direction the bot is orbiting
*/
enum OrbitDirection
{
	noOrbit,
	clockwiseOrbit,
	counterClockwiseOrbit
}

// *********************************************************************************
// VARIABLES
// *********************************************************************************

bool botEnabled;
bool mapChanged;

// Voting for bot
int numVoters = 0;
int numVotes = 0;
int numVotesNeeded = 0;
bool voted[MAXPLAYERS + 1] = {false, ...};
bool canVote;
float votePercentage = 0.5;

int whichScore;

// The next time the client can airblast
float nextAirblastTime[MAXPLAYERS + 1];

// The direction each client is orbiting
OrbitDirection clientOrbitDir[MAXPLAYERS + 1];
// The clients position before orbiting
float clientOrbitPos[MAXPLAYERS + 1][3];
// The rockets that will be orbited
int orbitRocketRefs[MAXPLAYERS + 1][MAX_ROCKETS];
// The bot will only be focusing on airblasting one rocket at a time
int priorityAirblastRefs[MAXPLAYERS + 1];
// The vector that the client will always be looking at
float lookAtVector[MAXPLAYERS + 1][3];
// The turn rate at which to look at the lookAtVector
float lookSpeed[MAXPLAYERS + 1];

// The rocket entity reference
int rocketEntityRef[MAX_ROCKETS];
// Used to determine whether a rocket is valid
bool isRocketValid[MAX_ROCKETS];
// The name of the rocket
char rocketName[MAX_ROCKETS][PLATFORM_MAX_PATH];
// The index for the rocket class
int rocketClassIndex[MAX_ROCKETS];
// The number of deflections
int numRocketDeflections[MAX_ROCKETS];
// Determines whether a rocket is a spawn
bool isSpawnRocket[MAX_ROCKETS];
// Determines whether a rocket is a redirect
bool isRedirect[MAX_ROCKETS];
// The current speed of the rocket
float rocketSpeed[MAX_ROCKETS];
// The current turn rate of the rocket
float rocketTurnRate[MAX_ROCKETS];
// The predicted targets for each client
int predictedTargets[MAX_ROCKETS];

// The up direction. Value is initialized in init bots
float up[3];
float angle;

/*
* Important rocket parameters
* Default indices:
* 0 - Homing rocket
* 1 - Nuke
*/
char rocketClassName[MAX_ROCKET_CLASSES][PLATFORM_MAX_PATH];
char rocketClassModel[MAX_ROCKET_CLASSES][PLATFORM_MAX_PATH];

float rocketClassSpeed[MAX_ROCKET_CLASSES];
float rocketClassSpeedIncrement[MAX_ROCKET_CLASSES];

float rocketClassTurnRate[MAX_ROCKET_CLASSES];
float rocketClassTurnRateIncrement[MAX_ROCKET_CLASSES];

float rocketClassPlayerModifier[MAX_ROCKET_CLASSES];
float rocketClassModifier[MAX_ROCKET_CLASSES];
float rocketClassDirModifier[MAX_ROCKET_CLASSES];

// *********************************************************************************
// PLUGIN
// *********************************************************************************

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = "A bot that can handle 1-2 rockets in dodgeball",
	version = PLUGIN_VERSION,
	url = PLUGIN_CONTACT
}

// *********************************************************************************
// GENERAL
// *********************************************************************************

public OnPluginStart()
{
	CreateConVar("sm_pandaBot_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	
	HookEvent("arena_round_start", OnRoundStart, EventHookMode_PostNoCopy);
	HookEvent("arena_round_start", OnRoundStart, EventHookMode_PostNoCopy);
	HookEvent("arena_win_panel", OnRoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	
	RegAdminCmd("sm_pbot", bot_Cmd, ADMFLAG_RCON, "Force enable/disable PvB.");
	//RegConsoleCmd("sm_votepvb", votePvB_Cmd, "Vote to enable/disable PvB");
}

public OnConfigsExecuted()
{
	parseDodgeballConfiguration();
}

public OnClientConnected(client)
{
	if (IsFakeClient(client)) return;
	
	
}

public OnClientDisconnect(client)
{
	if (IsFakeClient(client)) return;
	
	
}

/*public Action:votePvB_Cmd(client, args)
{
	if (!GetConVarBool(cvarEnable) || GetConVarInt(cvarVoteMode) == 0) return Plugin_Handled;
	
	if (GetConVarInt(cvarVoteMode) != 2) AttemptPvBVotes(client);
	else
	{
		PvBVoteMenu();
	}
	return Plugin_Handled;
}*/

public void OnMapStart()
{
	CreateTimer(5.0, timer_mapStart);
	EnableBot();
}

public void OnMapEnd()
{
	mapChanged = true;
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) 
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int inflictor = GetEventInt(event, "inflictor_entindex");
	
	if (isValidClient(victim, false))
	{
		int index = -1;
		
		while ((index = findNextValidRocket(index)) != -1)
		{
			if (predictedTargets[index] == victim)
			{
				isRedirect[index] = true;
			}
		}
	}
	
	SetRandomSeed(_:GetGameTime());
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	SetRandomSeed(GetTime());
	initBots();
	
	whichScore = GetRandomInt(0, 1);
	//PrintToChatAll("%i", whichScore);
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	
}

public Action timer_mapStart(Handle timer)
{
	mapChanged = false;
}

public OnGameFrame()
{
	ChangePlayerTeam();
	
	int index = -1;
	
	// Manages all the rockets
	while ((index = findNextValidRocket(index)) != -1)
	{
		if (isSpawnRocket[index] == true || isRedirect[index] == true)
		{
			// Constantly checks the predicted target if the rocket is a spawn
			// This is because when the rocket spawns, the team is 0 (not sure why) and so this is a small fix
			calculatePredictedTargets(index, index);
		}
		
		// Checks whether a rocket has been airblasted
		if (checkDeflected(index))
		{
			numRocketDeflections[index]++;
			isSpawnRocket[index] = false;
			isRedirect[index] = false;
			rocketSpeed[index] += rocketClassSpeedIncrement[rocketClassIndex[index]];
			rocketTurnRate[index] += rocketClassTurnRateIncrement[rocketClassIndex[index]];
			
			calculatePredictedTargets(index, index);
		}
	}
	
	// Disable the bot
	//if (mapChanged && botEnabled) DisableBot();
}

public void OnEntitySpawned(int entity)
{
	// Checks whether the entity is a nuke or a rocket
	char classname[32];
	
	if (GetEntityClassname(entity, classname, sizeof(classname)))
	{
		// Checks whether the entity is a nuke or a rocket
		if (StrEqual(classname, "tf_projectile_sentryrocket") || StrEqual(classname, "tf_projectile_rocket"))
		{
			addRocket(entity);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	SDKHook(entity, SDKHook_SpawnPost, OnEntitySpawned);
}

public void OnEntityDestroyed(int entity)
{
	char classname[32];
	
	if (GetEntityClassname(entity, classname, sizeof(classname)))
	{
		// Checks whether the entity is a nuke or a rocket
		if (StrEqual(classname, "tf_projectile_sentryrocket") || StrEqual(classname, "tf_projectile_rocket"))
		{
			removeRocket(entity);
		}
	}
}

public Action:bot_Cmd(client, args)
{
	if (!botEnabled) 
	{
		EnableBot();
	}
	else 
	{
		DisableBot();
		ServerCommand("mp_scrambleteams");
	}
	return Plugin_Handled;
}

EnableBot()
{
	ServerCommand("tf_bot_quota 0");
	ServerCommand("mp_autoteambalance 0");
	ServerCommand("tf_bot_add 1 Pyro blue easy \"%s\"", "Panda Bot");
	//ServerCommand("tf_bot_add 1 Pyro red easy \"%s\"", "Second Bot");
	//ServerCommand("tf_bot_add 1 Pyro blue easy \"%s\"", "Third Bot");
	ServerCommand("tf_bot_keep_class_after_death 1");
	ServerCommand("tf_bot_taunt_victim_chance 0");
	ServerCommand("tf_bot_join_after_player 0");
	
	PrintToChatAll("\x01[\x03%s\x01]\x04 PvB Enabled.", PLUGIN_NAME);
	botEnabled = true;
}

DisableBot()
{
	ServerCommand("tf_bot_kick all");
	ServerCommand("tf_bot_quota 0");
	
	PrintToChatAll("\x01[\x03%s\x01]\x04 PvB Disabled.", PLUGIN_NAME);
	botEnabled = false;
}

// *********************************************************************************
// DODGEBALL
// *********************************************************************************

/*
* Initialize client parameters at the start of each round
*/
void initBots()
{
	up[2] = 1.0;
	
	for (int c = 0; c < MAXPLAYERS + 1; c++)
	{
		if (!isValidClient(c))
			continue;
		
		clientOrbitDir[c] = noOrbit;
		
		float clientPos[3];
		GetClientAbsOrigin(c, clientPos);
		
		setClientOrbitPos(c, clientPos);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || !isValidClient(client))
	{
		return Plugin_Continue;
	}
	
	int currentWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	
	if (currentWeapon != -1)
	{
		updateNextAirblast(client, currentWeapon);
	}
	
	if (isClientBot(client))
	{
		controlClient(client, currentWeapon, buttons, vel);
		
		/*float radius = 100.0;
		
		vel[0] = Cosine(angle * DEG_TO_RAD) * radius * PYRO_SPEED;
		vel[1] = Sine(angle * DEG_TO_RAD) * radius * PYRO_SPEED;
		
		angle += PYRO_SPEED / (2 * PI * radius);
		
		if (angle >= 360.0)
			angle = 0.0;*/
	}
	else
	{
		//lookAtEntity(client, 1, 0.2);
		//controlClient(client, currentWeapon, buttons, vel);
		//PrintToChatAll("%.2f %.2f %.2f", vel[0], vel[1], vel[2]);
	}
	
	return Plugin_Continue;
}

/*
* Used to control the client. Plays dodgeball
*/
void controlClient(int client, int currentWeapon, int &buttons, int vel[3])
{
	int numTargeting;
	int rocketRefIds[MAX_ROCKETS];
	int airblastRocketRef;
	int orbitRocketRefIds[MAX_ROCKETS];
	
	getPredictedTargets(client, numTargeting, rocketRefIds);
	strategy(client, currentWeapon, rocketRefIds, airblastRocketRef, orbitRocketRefIds, numTargeting);
	
	if (numTargeting > 0)
	{
		if (orbitRocketRefIds[0] != ARRAY_END)
			orbitRockets2(client, vel, orbitRocketRefIds);
		
		//if (airblastRocketRef != ARRAY_END)
		//	airblastRocket(client, airblastRocketRef, buttons, currentWeapon);
	}
	else
	{
		airblastRocketRef = ARRAY_END;
		orbitRocketRefIds[0] = ARRAY_END;
	}
	
	if (orbitRocketRefIds[0] == ARRAY_END)
	{
		clientOrbitDir[client] = noOrbit;
	}
	
	if (clientOrbitDir[client] == noOrbit)
	{
		//PrintToChatAll("%.2f %.2f %.2f", clientOrbitPos[client][0], clientOrbitPos[client][1], clientOrbitPos[client][2]);
		movePlayer(client, clientOrbitPos[client], vel);
	}
}

/*
* The strategy of the bots
*/
void strategy(int client, int weapon, int rocketRefIds[MAX_ROCKETS], int &airblastRocketRef, int orbitRocketRefIds[MAX_ROCKETS], int numTargeting)
{
	// The best orbit score. Lower the better
	float bestOrbitScore = 100.0;
	int bestOrbitRocketId;
	
	// Calculates the orbit score of each other
	for (int i = 0; i < MAX_ROCKETS; i++)
	{
		if (rocketRefIds[i] == ARRAY_END)
		{
			break;
		}
		
		float cRocketSpeed = rocketSpeed[rocketRefIds[i]];
		float turnRate = rocketTurnRate[rocketRefIds[i]];
		float score = 0.0;
		
		if (whichScore == 0)
		{
			score = calculateOrbitScore(cRocketSpeed, turnRate);
		}
		else if (whichScore == 1)
		{
			score = calculateRandomScore();
		}
		
		if (score < bestOrbitScore || bestOrbitScore == 100.0)
		{
			bestOrbitScore = score;
			bestOrbitRocketId = i;
		}
	}
	
	orbitRocketRefIds[0] = rocketRefIds[bestOrbitRocketId];
	
	for (int i = 0; i < MAX_ROCKETS; i++)
	{
		if (rocketRefIds[i] == ARRAY_END)
		{
			break;
		}
		
		if (bestOrbitRocketId != i || numTargeting == 1)
		{
			airblastRocketRef = rocketRefIds[i];
			break;
		}
	}
}

/*
* Calculates the orbit score
*/
float calculateOrbitScore(float speed, float turnRate)
{
	float turnRateScore = normValue(turnRate, 0.175, 0.5);
	float speedScore = normValue(speed, 2000.0, 6000.0);

	// Turn rate plays a larger factor than speed does
	float orbitScore = normValue(turnRateScore + ((speedScore + 0.01) * (turnRateScore + 0.01)), 0.0, 1.0);
	
	return orbitScore;
}

/*
* Calculates a random score
*/
float calculateRandomScore()
{
	// Turn rate plays a larger factor than speed does
	float randomScore = GetRandomFloat(0.0, 1.0);
	
	return randomScore;
}

/*
* Moves client to a position
*/
void movePlayer(int client, float newPos[3], float vel[3])
{
	float clientPos[3];
	float clientToPos[3];
	float length;
	
	GetClientAbsOrigin(client, clientPos);
	
	SubtractVectors(newPos, clientPos, clientToPos);
	length = GetVectorLength(clientToPos, false);
	
	//PrintToChatAll("%.2f %.2f %.2f", clientToPos[0], clientToPos[1], length);
	
	if (length >= 100.0)
	{
		//vel[0] = clientToPos[0] > 0.0 ? PYRO_SPEED : -PYRO_SPEED;
		//vel[1] = clientToPos[1] > 0.0 ? -PYRO_SPEED : PYRO_SPEED;
		NormalizeVector(clientToPos, clientToPos);
		//PrintToChatAll("%.2f %.2f %.2f", clientToPos[0], clientToPos[1], length);
		vel[0] = clientToPos[0] * PYRO_SPEED;
		vel[1] = clientToPos[1] * -PYRO_SPEED;
	}
}

/*
* Looks at a rocket and airblasts the rocket
*/
void airblastRocket(int client, int rocketRefId, int &buttons, int weapon)
{
	float clientEyePos[3];
	float clientPos[3];
	float clientEyeAngles[3];
	float clientForward[3];
	float rocketPos[3];
	float clientToRocket[3];
	float rocketDist;
	float angle;
	int rocketId = EntRefToEntIndex(rocketEntityRef[rocketRefId]);
	
	GetClientEyePosition(client, clientEyePos);
	GetClientAbsOrigin(client, clientPos);
	GetEntPropVector(rocketId, Prop_Send, "m_vecOrigin", rocketPos);
	rocketDist = GetVectorDistance(clientEyePos, rocketPos);
	
	if (rocketDist <= NORM_DIST)
	{
		// Look at the rocket
		//lookAt(client, rocketPos, 0.3);
		
		//lookAtEntity(client, rocketRefId, 0.3);
		
		float angle[3];
		angle[0] = 0.0 - RadToDeg(ArcTangent((rocketPos[2] - clientEyePos[2]) / (FloatAbs(SquareRoot(Pow(clientEyePos[0] - rocketPos[0], 2.0) + Pow(rocketPos[1] - clientEyePos[1], 2.0))))));
		angle[1] = GetAngle(clientEyePos, rocketPos);
		TeleportEntity(client, NULL_VECTOR, angle, NULL_VECTOR);
	}
	
	// Checks where the client is looking at. If not looking where the rocket is, do not airblast
	GetClientEyeAngles(client, clientEyeAngles);
	GetAngleVectors(clientEyeAngles, clientForward, NULL_VECTOR, NULL_VECTOR);
	SubtractVectors(rocketPos, clientEyePos, clientToRocket);
	
	NormalizeVector(clientToRocket, clientToRocket);
	
	angle = ArcCosine(GetVectorDotProduct(clientForward, clientToRocket)) * RAD_TO_DEG;
	
	// Airblast the rocket if certain conditions are met
	if (rocketDist <= 200.0 && canAirblast(client, weapon) && angle <= 25.0)
	{
		buttons |= IN_ATTACK2;
		lookAtEntity(client, rocketId, 0.3);
		// Set the next time the client can airblast
		updateNextAirblast(client, weapon);
	}
}

/*
* Orbits a list of rockets
* The orbiting may not be perfect
* Trying out the circle formula orbits
* Assumption: Assumes all rockets are going in the same direction
*/
void orbitRockets2(int client, float vel[3], int rocketRefIds[MAX_ROCKETS])
{
	float clientEyePos[3];
	float clientEyeAngles[3];
	float clientForward[3];
	float rocketPos[3];
	float rocketVel[3];
	float clientToRocketCross[3];
	float clientToRocket[3];
	float clientToRocketDist;
	
	// Get client values
	GetClientEyePosition(client, clientEyePos);
	GetClientEyeAngles(client, clientEyeAngles);
	GetAngleVectors(clientEyeAngles, clientForward, NULL_VECTOR, NULL_VECTOR);
	
	int rocket = EntRefToEntIndex(rocketEntityRef[rocketRefIds[0]]);
	
	// Get rocket values
	GetEntPropVector(rocket, Prop_Send, "m_vecOrigin", rocketPos);
	GetEntPropVector(rocket, Prop_Data, "m_vecAbsVelocity", rocketVel);
	
	// Get the vector from the client to the rocket position
	SubtractVectors(rocketPos, clientEyePos, clientToRocket);
	clientToRocketDist = GetVectorLength(clientToRocket);
	
	// Only orbit the rocket if it is close
	if (clientToRocketDist <= ORBIT_DIST)
	{
		//Orbit the rocket
		// Calculate a vector perpendicular to the up and clientToRocket vector
		// This vector tells us which direction to move in
		GetVectorCrossProduct(up, clientToRocket, clientToRocketCross);
		
		OrbitDirection od = directionToOrbit(client, rocket);
		clientOrbitDir[client] = od;
		
		if (od == noOrbit)
		{
			float clientPos[3];
			GetClientAbsOrigin(client, clientPos);
			
			setClientOrbitPos(client, clientPos);
		}
		
		if (od == counterClockwiseOrbit)
		{
			ScaleVector(clientToRocketCross, -1.0);
		}
		
		// Calculate the direction the client should be moving in
		float angle = ArcCosine(GetVectorDotProduct(clientToRocketCross, clientForward) / GetVectorLength(clientToRocketCross));
		float cross[3];
		GetVectorCrossProduct(clientToRocketCross, clientForward, cross);
		if (cross[2] < 0.0)
		{
			angle *= -1.0;
		}
		
		float circlePos[3];
		float radius = 10.0;
		
		circlePos[0] = rocketPos[0] + Cosine(angle) * radius;
		circlePos[1] = rocketPos[1] + Sine(angle) * radius;
		circlePos[2] = rocketPos[2];
		
		//angle += PYRO_SPEED / (2 * PI * radius);
		
		// Move in a circular motion
		vel[0] = Cosine(angle * DEG_TO_RAD) * radius * PYRO_SPEED;
		vel[1] = Sine(angle * DEG_TO_RAD) * radius * PYRO_SPEED;
	}
}

/*
* Orbits a list of rockets
* The orbiting may not be perfect
* Assumption: Assumes all rockets are going in the same direction
*/
void orbitRockets(int client, float vel[3], int rocketRefIds[MAX_ROCKETS])
{
	float clientEyePos[3];
	float clientEyeAngles[3];
	float clientForward[3];
	float rocketPos[3];
	float rocketVel[3];
	float clientToRocketCross[3];
	float clientToRocket[3];
	float clientToRocketDist;
	
	// Get client values
	GetClientEyePosition(client, clientEyePos);
	GetClientEyeAngles(client, clientEyeAngles);
	GetAngleVectors(clientEyeAngles, clientForward, NULL_VECTOR, NULL_VECTOR);
	
	int rocket = EntRefToEntIndex(rocketEntityRef[rocketRefIds[0]]);
	
	// Get rocket values
	GetEntPropVector(rocket, Prop_Send, "m_vecOrigin", rocketPos);
	GetEntPropVector(rocket, Prop_Data, "m_vecAbsVelocity", rocketVel);
	
	// Get the vector from the client to the rocket position
	SubtractVectors(rocketPos, clientEyePos, clientToRocket);
	clientToRocketDist = GetVectorLength(clientToRocket);
	
	// Only orbit the rocket if it is close
	if (clientToRocketDist <= ORBIT_DIST)
	{
		//Orbit the rocket
		// Calculate a vector perpendicular to the up and clientToRocket vector
		// This vector tells us which direction to move in
		GetVectorCrossProduct(up, clientToRocket, clientToRocketCross);
		
		OrbitDirection od = directionToOrbit(client, rocket);
		clientOrbitDir[client] = od;
		
		if (od == noOrbit)
		{
			float clientPos[3];
			GetClientAbsOrigin(client, clientPos);
			
			setClientOrbitPos(client, clientPos);
		}
		
		if (od == counterClockwiseOrbit)
		{
			ScaleVector(clientToRocketCross, -1.0);
		}
		
		// Calculate the direction the client should be moving in
		float angle = ArcCosine(GetVectorDotProduct(clientToRocketCross, clientForward) / GetVectorLength(clientToRocketCross));
		float cross[3];
		GetVectorCrossProduct(clientToRocketCross, clientForward, cross);
		if (cross[2] < 0.0)
		{
			angle *= -1.0;
		}
		
		// Move in a circular motion
		//vel[0] = Cosine(angle) > 0.0 ? PYRO_SPEED : -PYRO_SPEED;
		//vel[1] = Sine(angle) > 0.0 ? PYRO_SPEED : -PYRO_SPEED;
		vel[0] = Cosine(angle) * PYRO_SPEED;
		vel[1] = Sine(angle) * PYRO_SPEED;
	}
}

/*
* Returns the direction needed to orbit a particular rocket
* In other words, will determine whether the rocket is to the left or right of the bot
*/
OrbitDirection directionToOrbit(int client, int rocketId)
{
	float clientEyePos[3];
	float rocketPos[3];
	float rocketVel[3];
	float rocketToClient[3];
	float rocketToClientRight[3];
	float dot;
	
	GetEntPropVector(rocketId, Prop_Send, "m_vecOrigin", rocketPos);
	GetEntPropVector(rocketId, Prop_Data, "m_vecAbsVelocity", rocketVel);
	
	GetClientEyePosition(client, clientEyePos);
	
	// Get the vector between the client and the rocket
	SubtractVectors(rocketPos, clientEyePos, rocketToClient);
	
	// Get which side is right for the rocketToClient vector
	GetVectorCrossProduct(rocketToClient, up, rocketToClientRight);
	NormalizeVector(rocketToClientRight, rocketToClientRight);
	NormalizeVector(rocketVel, rocketVel);
	// Determines whether the client should orbit clockwise
	dot = GetVectorDotProduct(rocketToClientRight, rocketVel);
	return dot >= 0.0 ? clockwiseOrbit : counterClockwiseOrbit;
}

/*
* Sets the clients orbit position
*/
void setClientOrbitPos(int client, float clientPos[3])
{
	ScaleVector(clientOrbitPos[client], 0.0);
	AddVectors(clientOrbitPos[client], clientPos, clientOrbitPos[client]);
}

/*
* Determines whether the rocket is above, normal or below the eye level of the client
* Result vector -> [left (-ve) or right(+ve), up (+ve) or down(-ve)]
*/
void determineRocketPos(int client, int rocketId, float result[2])
{
	float clientEyePos[3];
	float clientEyeAngles[3];
	float clientForward[3];
	float clientRight[3];
	float clientToRocket[3];
	float dot;
	float rocketPos[3];
	float upOffset = 25.0;
	float downOffset = 70.0;
	float upDownDist;
	float leftRightDist;
	
	GetClientEyePosition(client, clientEyePos);
	GetClientEyeAngles(client, clientEyeAngles);
	GetAngleVectors(clientEyeAngles, clientForward, clientRight, NULL_VECTOR);
	GetEntPropVector(rocketId, Prop_Send, "m_vecOrigin", rocketPos);
	SubtractVectors(rocketPos, clientEyePos, clientToRocket);
	
	NormalizeVector(clientToRocket, clientToRocket);
	
	upDownDist = FloatAbs(rocketPos[2] - clientEyePos[2]);
	leftRightDist = FloatAbs(rocketPos[0] - clientEyePos[0]);
	
	// [2] or the z direction is the vertical axis
	if (rocketPos[2] > clientEyePos[2] && upDownDist >= upOffset)
	{
		// Rocket is above client
		result[1] = upDownDist;
	}
	else if (rocketPos[2] < clientEyePos[2] && upDownDist >= downOffset)
	{
		// Rocket is below client
		result[1] = -1.0 * upDownDist;
	}
	
	// Check if the rocket is to the left or right of the bot
	dot = GetVectorDotProduct(clientToRocket, clientRight);
	
	if (dot <= 0)
	{
		result[0] = -1.0 * leftRightDist;
	}
	else
	{
		result[0] = leftRightDist;
	}
}

/*
* Updates the look at vector
*/
void updateLookAtVector(int client, float vec[3], float speed)
{
	lookAtVector[client][0] = vec[0];
	lookAtVector[client][1] = vec[1];
	lookAtVector[client][2] = vec[2];
	
	lookSpeed[client] = speed;
}

/*
* Sets the lookAtVector to look at the entity
*/
bool lookAtEntity(int client, int entityId, float speed)
{
	float entityPos[3];
	float clientEyePos[3];
	float clientToEntity[3];
	float clientForward[3];
	float clientEyeAngles[3];
	float newClientEyeAngles[3];
	
	GetClientEyePosition(client, clientEyePos);
	GetClientEyeAngles(client, clientEyeAngles);
	GetAngleVectors(clientEyeAngles, clientForward, NULL_VECTOR, NULL_VECTOR);
	
	GetEntPropVector(entityId, Prop_Send, "m_vecOrigin", entityPos);
	
	MakeVectorFromPoints(clientEyePos, entityPos, clientToEntity);
	NormalizeVector(clientToEntity, clientToEntity);
	
	updateLookAtVector(client, clientToEntity, speed);
}

/*
* Smoothly looks at a vector
* Returns true if the client is looking at the vector location
*/
bool lookAt(int client, float vec[3], float speed)
{
	float clientEyePos[3];
	float clientToEntity[3];
	float clientForward[3];
	float clientEyeAngles[3];
	float newClientEyeAngles[3];
	
	// Collect useful client information
	GetClientEyePosition(client, clientEyePos);
	GetClientEyeAngles(client, clientEyeAngles);
	GetAngleVectors(clientEyeAngles, clientForward, NULL_VECTOR, NULL_VECTOR);
	
	NormalizeVector(clientEyePos, clientEyePos);
	NormalizeVector(vec, vec);
	
	MakeVectorFromPoints(clientEyePos, vec, clientToEntity);
	NormalizeVector(clientToEntity, clientToEntity);
	
	// Smoothly move towards the vector
	lerp(clientForward, vec, clientForward, speed);
	
	// Teleport the clients eye angles to the new angles
	GetVectorAngles(clientForward, newClientEyeAngles);
	TeleportEntity(client, NULL_VECTOR, newClientEyeAngles, NULL_VECTOR);
	
	if (GetVectorDistance(clientEyeAngles, newClientEyeAngles) <= 0.04)
	{
		return true;
	}
	
	return false;
}

/*
* Returns a float that will try to predict the time the rocket will hit a client
* Only uses straight distance
*/
float predictRocketHitTime(int client, int rocketId)
{
	float clientOrigin[3];
	float rocketPos[3];
	float rocketVel[3];
	float clientToRocket[3];
	float distance;
	float speed;
	float time;
	
	GetEntPropVector(rocketId, Prop_Send, "m_vecOrigin", rocketPos);
	GetEntPropVector(rocketId, Prop_Data, "m_vecAbsVelocity", rocketVel);
	GetClientAbsOrigin(client, clientOrigin);
	
	SubtractVectors(rocketPos, clientOrigin, clientToRocket);
	distance = GetVectorLength(clientToRocket);
	speed = GetVectorLength(rocketVel);
	
	time = distance / speed;
	
	return time;
}

/*
* Calculates the predicted rocket targets. Will not be 100% accurate at times. That is why it is only predicting
*/
void calculatePredictedTargets(int index, int rocketRefId)
{
	int target = -1;
	float targetWeight = 0.0;
	float rocketPos[3];
	float rocketDir[3];
	float rocketAngles[3];
	float rocketTeam;
	
	int entity = EntRefToEntIndex(rocketEntityRef[rocketRefId]);
	int class = rocketClassIndex[rocketRefId];
	float weight = rocketClassDirModifier[class];
	
	rocketTeam = GetEntProp(entity, Prop_Send, "m_iTeamNum", 1);
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", rocketPos);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", rocketAngles);
	GetAngleVectors(rocketAngles, rocketDir, NULL_VECTOR, NULL_VECTOR);
	
	for (int client = 0; client <= MaxClients; client++)
	{    
		// If the client isn't connected, skip.
		if (!isValidClient(client)) continue;
		if (TF2_GetClientTeam(client) == rocketTeam) continue;
		
		// Determine if this client should be the target.
		float newWeight = 0.0;
		
		float clientPos[3];
		GetClientEyePosition(client, clientPos);
		float directionToClient[3];
		MakeVectorFromPoints(rocketPos, clientPos, directionToClient);
		
		newWeight += GetVectorDotProduct(rocketDir, directionToClient) * weight;
		
		if ((target == -1) || newWeight >= targetWeight)
		{
			target = client;
			targetWeight = newWeight;
		}
	}
	
	predictedTargets[index] = target;
	/*char clientName[32];
	GetClientName(target, clientName, sizeof(clientName));
	
	PrintToChatAll("Target: %s, weight: %.2f", clientName, targetWeight);*/
}

/*
* Collects all the rockets that are targeting a client
*/
void getPredictedTargets(int client, int &numTargeting, int rocketRefs[MAX_ROCKETS])
{
	int index = -1;
	int i = 0;
	
	// Goes through all the valid rockets
	while ((index = findNextValidRocket(index)) != -1)
	{
		
		// If it is the predicted target
		if (predictedTargets[index] == client)
		{
			rocketRefs[i++] = index;
			numTargeting++;
		}
	}
	
	// Used to know when to stop
	rocketRefs[i] = ARRAY_END;
}

// *********************************************************************************
// ROCKETS
// *********************************************************************************

/*
* Checks whether the rocket was deflected
*/
bool checkDeflected(index)
{
	int entity = EntRefToEntIndex(rocketEntityRef[index]);
	int numDeflections = GetEntProp(entity, Prop_Send, "m_iDeflected") - 1;
	
	if (numDeflections > numRocketDeflections[index])
	{
		return true;
	}
	
	return false;
}

/*
* Adds the rocket to the rocket arrays and any other important things to init the rockets
*/
void addRocket(int rocketIndex)
{
	int newIndex = findFreeRocketSlot();
	
	if (newIndex != -1)
	{
		isRocketValid[newIndex] = true;
		isSpawnRocket[newIndex] = true;
		rocketEntityRef[newIndex] = EntIndexToEntRef(rocketIndex);
		numRocketDeflections[newIndex] = 0;
		
		char modelName[PLATFORM_MAX_PATH];
		GetEntPropString(rocketIndex, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
		
		for (int c = 0; c < MAX_ROCKET_CLASSES; c++)
		{
			if (StrEqual(modelName, rocketClassModel[c]))
			{
				rocketClassIndex[newIndex] = c;
				rocketName[newIndex] = rocketClassName[c];
				rocketSpeed[newIndex] = rocketClassSpeed[c];
				rocketTurnRate[newIndex] = rocketClassTurnRate[c];
			}
		}
	}
}

/*
* Removes a rocket from the array
* Searches the whole array for the rocketIndex
*/
void removeRocket(int rocketIndex)
{
	for(int i = 0; i < MAX_ROCKETS; i++)
	{
		if (EntRefToEntIndex(rocketEntityRef[i]) == rocketIndex)
		{
			isRocketValid[i] = false;
		}
	}
}

/*
* Tries and finds a valid index in the arrays for a valid rocket
* Returns -1 if a slot cannot be found
*/
int findFreeRocketSlot()
{
	int currIndex = 0;
	
	do
	{
		if (!isValidRocket(currIndex))
		{
			return currIndex;
		}
		
		if ((++currIndex) == MAX_ROCKETS)
		{
			currIndex = 0;
		}
	} while (currIndex != 0);
	
	return -1;
}

/*
* Checks whether the entity index is a valid rocket entity
*/
bool isValidRocket(int rocketIndex)
{
	if (rocketIndex >= 0 && isRocketValid[rocketIndex] == true)
	{
		if (EntRefToEntIndex(rocketEntityRef[rocketIndex]) == -1)
		{
			isRocketValid[rocketIndex] = false;
			
			return false;
		}
		
		return true;
	}
	
	return false;
}

/*
* Finds a rocket index from it's entity.
*/
int findRocketByEntity(entity)
{
	int index = -1;
	
	while ((index = findNextValidRocket(index)) != -1)
		if (EntRefToEntIndex(rocketEntityRef[index]) == entity)
			return index;
		
	return -1;
}

/*
* Retrieves the index of the next valid rocket from the current offset
*/
int findNextValidRocket(int rocketIndex, bool wrap = false)
{
	for (new current = rocketIndex + 1; current < MAX_ROCKETS; current++)
	{
		if (isValidRocket(current))
		{
			return current;
		}
	}
		
	return (wrap == true) ? findNextValidRocket(-1) : -1;
}

stock float calculateModifier(iClass, iDeflections)
{
	return  iDeflections + 
	(g_iRocketsFired * g_fRocketClassRocketsModifier[iClass]) + 
	(g_iPlayerCount * g_fRocketClassPlayerModifier[iClass]);
}

// *********************************************************************************
// CONFIG
// *********************************************************************************

/*
* Parses the dodgeball configuration file. Hopefully it exists
*/
void parseDodgeballConfiguration(char configFile[] = "general.cfg")
{
	// Parse configuration
	char path[PLATFORM_MAX_PATH];
	char filename[PLATFORM_MAX_PATH];
	
	Format(filename, sizeof(filename), "configs/dodgeball/%s", configFile);
	BuildPath(Path_SM, path, sizeof(path), filename);
	
	// Try to parse the dodgeball config file if it exists
	if (FileExists(path, true))
	{
		KeyValues dbConfig = new KeyValues("tf2_dodgeball");
		
		if (FileToKeyValues(dbConfig, path) == false)
		{
			SetFailState("Error while parsing the dodgeball configuration file.");
		}
		
		dbConfig.GotoFirstSubKey();
		
		// Get each of the different bot difficulties
		do
		{
			char section[64];
			dbConfig.GetSectionName(section, sizeof(section));
			
			if (StrEqual(section, "classes"))
			{
				parseClasses(dbConfig);
			}
		}
		while (dbConfig.GotoNextKey());
		
		delete dbConfig;
	}
}

/*
* Parses the classes section of the dodgeball file
*/
void parseClasses(KeyValues dbConfig)
{
	char sectionName[PLATFORM_MAX_PATH];
	char className[PLATFORM_MAX_PATH];
	int class = 0;
	
	dbConfig.GotoFirstSubKey();
	
	do
	{
		// The name of the class
		dbConfig.GetString("name", className, sizeof(className));
		strcopy(rocketClassName[class], PLATFORM_MAX_PATH, className);
		
		// The name of the model
		dbConfig.GetString("model", className, sizeof(className));
		strcopy(rocketClassModel[class], PLATFORM_MAX_PATH, className);
		
		if (StrEqual(rocketClassModel[class], ""))
		{
			// The default rocket model
			rocketClassModel[class] = "models/weapons/w_models/w_rocket.mdl";
		}
		
		// Parameters
		rocketClassSpeed[class] = dbConfig.GetFloat("speed");
		rocketClassSpeedIncrement[class] = dbConfig.GetFloat("speed increment");
		rocketClassTurnRate[class] = dbConfig.GetFloat("turn rate");
		rocketClassTurnRateIncrement[class] = dbConfig.GetFloat("turn rate increment");
		rocketClassPlayerModifier[class] = dbConfig.GetFloat("no. players modifier");
		rocketClassModifier[class] = dbConfig.GetFloat("no. rockets modifier");
		rocketClassDirModifier[class] = dbConfig.GetFloat("direction to target weight");
		
		class++;
	}
	while (dbConfig.GotoNextKey());
	
	dbConfig.GoBack();
}

// *********************************************************************************
// TOOLS
// *********************************************************************************

/*
* Returns true if the client a bot
*/
stock bool isClientBot(int client)
{
	return IsClientInGame(client) && IsFakeClient(client) && !IsClientReplay(client) && !IsClientSourceTV(client);
}

/*
* Checks if a client is valid
*/
stock bool isValidClient(int client, bool checkAlive = true)
{
	if(client <= 0 || client > MaxClients)
		return false;
	if(!IsClientInGame(client))
		return false;
	if (checkAlive && !IsPlayerAlive(client))
		return false;
	if(IsClientSourceTV(client) || IsClientReplay(client))
		return false;
	
	return true;
}

/*
* Gets a random client
*/

stock int getRandomClient(int client)
{
	int clients[MAXPLAYERS + 1];
	int clientCount;
	int numClients = GetClientCount(true);
	int clientTeam = GetClientTeam(client);
	
	for (int i = 1; i < numClients + 1; i++)
	{
		int team = GetClientTeam(i);
		
		if (IsClientInGame(i) && i != client && opponentTeam != TFTeam_Spectator && clientTeam != team)
		{
			clients[clientCount++] = i;
		}
	}
	
	return (clientCount == 0) ? -1 : clients[GetRandomInt(0, clientCount - 1)]; 
}

/*
* Gets the number of players on the clients team
*/
stock int getClientTeamCount(int client)
{
	int clientTeam = GetClientTeam(client);
	
	return GetTeamClientCount(clientTeam);
}

/*
* Sets the next time the client can airblast
*/
stock void updateNextAirblast(int client, int weapon)
{
	nextAirblastTime[client] = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
}

/*
* Returns true if the client can airblast
*/
stock bool canAirblast(int client, int weapon)
{
	float t = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack") - nextAirblastTime[client];
	return t <= 0.0;
}

stock ChangePlayerTeam()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientObserver(i) && GetClientTeam(i) != 2 && botEnabled)
		{
			ChangeClientTeam(i, 2);
			TF2_RespawnPlayer(i);
		}
	}
}

/*`
* Calculate the linear interpolation between two vectors. Stores result in third vector
*/
stock void lerp(float a[3], float b[3], float c[3], float t)
{
	if (t < 0.0) t = 0.0;
	if (t > 1.0) t = 1.0;
	
	//Move t units across from a to b
	c[0] = a[0] + (b[0] - a[0]) * t;
	c[1] = a[1] + (b[1] - a[1]) * t;
	c[2] = a[2] + (b[2] - a[2]) * t;
}

/*
* Normalizes a value between a min and max value
*/
stock float normValue(float value, float min, float max)
{
	return (value - min) / (max - min);
}

stock Float:GetAngle(const Float:coords1[3], const Float:coords2[3])
{
	new Float:angle = RadToDeg(ArcTangent((coords2[1] - coords1[1]) / (coords2[0] - coords1[0])));
	if (coords2[0] < coords1[0])
	{
		if (angle > 0.0) angle -= 180.0;
		else angle += 180.0;
	}
	return angle;
}

stock ModRateOfFire(weapon)
{
	new Float:m_flNextPrimaryAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
	new Float:m_flNextSecondaryAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack");
	SetEntPropFloat(weapon, Prop_Send, "m_flPlaybackRate", 10.0);

	new Float:fGameTime = GetGameTime();
	new Float:fPrimaryTime = ((m_flNextPrimaryAttack - fGameTime) - 0.99);
	new Float:fSecondaryTime = ((m_flNextSecondaryAttack - fGameTime) - 0.99);

	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", fPrimaryTime + fGameTime);
	SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", fSecondaryTime + fGameTime);
}

// *********************************************************************************
// END OF FILE
// *********************************************************************************
