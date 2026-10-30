// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Scott Lembcke and Howling Moon Software

#import <stdlib.h>
#import <stdio.h>
#import "chipmunk/chipmunk.h"

#import "ChipmunkDemo.h"

static void shapeFreeWrap(cpSpace *space, cpShape *shape, void *unused){
	cpSpaceRemoveShape(space, shape);
	cpShapeFree(shape);
}

static void postShapeFree(cpShape *shape, cpSpace *space){
	cpSpaceAddPostStepCallback(space, (cpPostStepFunc)shapeFreeWrap, shape, NULL);
}

static void constraintFreeWrap(cpSpace *space, cpConstraint *constraint, void *unused){
	cpSpaceRemoveConstraint(space, constraint);
	cpConstraintFree(constraint);
}

static void postConstraintFree(cpConstraint *constraint, cpSpace *space){
	cpSpaceAddPostStepCallback(space, (cpPostStepFunc)constraintFreeWrap, constraint, NULL);
}

static void bodyFreeWrap(cpSpace *space, cpBody *body, void *unused){
	cpSpaceRemoveBody(space, body);
	cpBodyFree(body);
}

static void postBodyFree(cpBody *body, cpSpace *space){
	cpSpaceAddPostStepCallback(space, (cpPostStepFunc)bodyFreeWrap, body, NULL);
}

// Safe and future proof way to remove and free all objects that have been added to the space.
void
ChipmunkDemoFreeSpaceChildren(cpSpace *space)
{
	// Must remove these BEFORE freeing the body or you will access dangling pointers.
	cpSpaceEachShape(space, (cpSpaceShapeIteratorFunc)postShapeFree, space);
	cpSpaceEachConstraint(space, (cpSpaceConstraintIteratorFunc)postConstraintFree, space);
	
	cpSpaceEachBody(space, (cpSpaceBodyIteratorFunc)postBodyFree, space);
}

void ChipmunkDemoDefaultDrawImpl(cpSpace *space){}


extern ChipmunkDemo bench_list[];
extern int bench_count;

#include <sys/time.h>
#include <unistd.h>

static double GetMilliseconds(){
	struct timeval time;
	gettimeofday(&time, NULL);
	
	return (time.tv_sec*1000.0 + time.tv_usec/1000.0);
}

static void time_trial(int index, int count)
{
	cpSpace *space = bench_list[index].initFunc();
	
	double start_time = GetMilliseconds();
	
	for(int i=0; i<count; i++)
		bench_list[index].updateFunc(space, 1.0/60.0);
	
	double end_time = GetMilliseconds();
	
	bench_list[index].destroyFunc(space);
	
	printf("Time(%c) = %8.2f ms (%s)\n", index + 'a', end_time - start_time, bench_list[index].name);
}


int main(int argc, char *argv[])
{
	printf("Starting Benchmarks.\n");
	for(int i=0; i<bench_count; i++) time_trial(i, 1000);
//	time_trial('g' - 'a', 10000);
	
	printf("Benchmarks Complete.\n");
	return 0;
}
