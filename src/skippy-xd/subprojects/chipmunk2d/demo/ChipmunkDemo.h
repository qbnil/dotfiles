// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Scott Lembcke and Howling Moon Software

#include "ChipmunkDebugDraw.h"

typedef struct ChipmunkDemo ChipmunkDemo;

typedef cpSpace *(*ChipmunkDemoInitFunc)(void);
typedef void (*ChipmunkDemoUpdateFunc)(cpSpace *space, double dt);
typedef void (*ChipmunkDemoDrawFunc)(cpSpace *space);
typedef void (*ChipmunkDemoDestroyFunc)(cpSpace *space);

struct ChipmunkDemo {
	const char *name;
	double timestep;
 
	ChipmunkDemoInitFunc initFunc;
	ChipmunkDemoUpdateFunc updateFunc;
	ChipmunkDemoDrawFunc drawFunc;
	
	ChipmunkDemoDestroyFunc destroyFunc;
};

static inline cpFloat
frand(void)
{
	return (cpFloat)rand()/(cpFloat)RAND_MAX;
}

static inline cpVect
frand_unit_circle(){
	cpVect v = cpv(frand()*2.0f - 1.0f, frand()*2.0f - 1.0f);
	return (cpvlengthsq(v) < 1.0f ? v : frand_unit_circle());
}

extern int ChipmunkDemoTicks;
extern double ChipmunkDemoTime;
extern cpVect ChipmunkDemoKeyboard;
extern cpVect ChipmunkDemoMouse;
extern cpBool ChipmunkDemoRightClick;
extern cpBool ChipmunkDemoRightDown;

extern char const *ChipmunkDemoMessageString;
void ChipmunkDemoPrintString(char const *fmt, ...);

extern cpShapeFilter GRAB_FILTER;
extern cpShapeFilter NOT_GRABBABLE_FILTER;

void ChipmunkDemoDefaultDrawImpl(cpSpace *space);
void ChipmunkDemoFreeSpaceChildren(cpSpace *space);
