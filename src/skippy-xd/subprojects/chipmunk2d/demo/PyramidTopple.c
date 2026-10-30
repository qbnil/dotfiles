// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Scott Lembcke and Howling Moon Software

#include "chipmunk/chipmunk.h"
#include "ChipmunkDemo.h"

static void
update(cpSpace *space, double dt)
{
	cpSpaceStep(space, dt);
}

#define WIDTH 4.0f
#define HEIGHT 30.0f

static void
add_domino(cpSpace *space, cpVect pos, cpBool flipped)
{
	cpFloat mass = 1.0f;
	cpFloat radius = 0.5f;
	cpFloat moment = cpMomentForBox(mass, WIDTH, HEIGHT);
	
	cpBody *body = cpSpaceAddBody(space, cpBodyNew(mass, moment));
	cpBodySetPosition(body, pos);

	cpShape *shape = (flipped ? cpBoxShapeNew(body, HEIGHT, WIDTH, 0.0) : cpBoxShapeNew(body, WIDTH - radius*2.0f, HEIGHT, radius));
	cpSpaceAddShape(space, shape);
	cpShapeSetElasticity(shape, 0.0f);
	cpShapeSetFriction(shape, 0.6f);
}

static cpSpace *
init(void)
{
	cpSpace *space = cpSpaceNew();
	cpSpaceSetIterations(space, 30);
	cpSpaceSetGravity(space, cpv(0, -300));
	cpSpaceSetSleepTimeThreshold(space, 0.5f);
	cpSpaceSetCollisionSlop(space, 0.5f);
	
	// Add a floor.
	cpShape *shape = cpSpaceAddShape(space, cpSegmentShapeNew(cpSpaceGetStaticBody(space), cpv(-600,-240), cpv(600,-240), 0.0f));
	cpShapeSetElasticity(shape, 1.0f);
	cpShapeSetFriction(shape, 1.0f);
	cpShapeSetFilter(shape, NOT_GRABBABLE_FILTER);
	
	
	// Add the dominoes.
	int n = 12;
	for(int i=0; i<n; i++){
		for(int j=0; j<(n - i); j++){
			cpVect offset = cpv((j - (n - 1 - i)*0.5f)*1.5f*HEIGHT, (i + 0.5f)*(HEIGHT + 2*WIDTH) - WIDTH - 240);
			add_domino(space, offset, cpFalse);
			add_domino(space, cpvadd(offset, cpv(0, (HEIGHT + WIDTH)/2.0f)), cpTrue);
			
			if(j == 0){
				add_domino(space, cpvadd(offset, cpv(0.5f*(WIDTH - HEIGHT), HEIGHT + WIDTH)), cpFalse);
			}
			
			if(j != n - i - 1){
				add_domino(space, cpvadd(offset, cpv(HEIGHT*0.75f, (HEIGHT + 3*WIDTH)/2.0f)), cpTrue);
			} else {
				add_domino(space, cpvadd(offset, cpv(0.5f*(HEIGHT - WIDTH), HEIGHT + WIDTH)), cpFalse);
			}
		}
	}
	
	return space;
}

static void
destroy(cpSpace *space)
{
	ChipmunkDemoFreeSpaceChildren(space);
	cpSpaceFree(space);
}

ChipmunkDemo PyramidTopple = {
	"Pyramid Topple",
	1.0/180.0,
	init,
	update,
	ChipmunkDemoDefaultDrawImpl,
	destroy,
};
