// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Scott Lembcke and Howling Moon Software

#include "chipmunk/chipmunk.h"

extern cpTransform ChipmunkDemoTextMatrix;

void ChipmunkDemoTextInit(void);
void ChipmunkDemoTextDrawString(cpVect pos, char const *str);
void ChipmunkDemoTextFlushRenderer(void);
void ChipmunkDemoTextClearRenderer(void);

void ChipmunkDemoTextPushRenderer(void);
void ChipmunkDemoTextPopRenderer(void);
