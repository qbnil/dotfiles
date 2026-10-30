// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Scott Lembcke and Howling Moon Software

static inline cpSpaceDebugColor RGBAColor(float r, float g, float b, float a){
	cpSpaceDebugColor color = {r, g, b, a};
	return color;
}

static inline cpSpaceDebugColor LAColor(float l, float a){
	cpSpaceDebugColor color = {l, l, l, a};
	return color;
}

void ChipmunkDebugDrawInit(void);

extern cpTransform ChipmunkDebugDrawVPMatrix;
extern float ChipmunkDebugDrawPointLineScale;

void ChipmunkDebugDrawCircle(cpVect pos, cpFloat angle, cpFloat radius, cpSpaceDebugColor outlineColor, cpSpaceDebugColor fillColor);
void ChipmunkDebugDrawSegment(cpVect a, cpVect b, cpSpaceDebugColor color);
void ChipmunkDebugDrawFatSegment(cpVect a, cpVect b, cpFloat radius, cpSpaceDebugColor outlineColor, cpSpaceDebugColor fillColor);
void ChipmunkDebugDrawPolygon(int count, const cpVect *verts, cpFloat radius, cpSpaceDebugColor outlineColor, cpSpaceDebugColor fillColor);
void ChipmunkDebugDrawDot(cpFloat size, cpVect pos, cpSpaceDebugColor fillColor);
void ChipmunkDebugDrawBB(cpBB bb, cpSpaceDebugColor outlineColor);

// Call this at the beginning of the frame to clear out any ChipmunkDebugDraw*() commands.
void ChipmunkDebugDrawClearRenderer(void);
// Call this at the end of the frame to draw the ChipmunkDebugDraw*() commands to the screen.
void ChipmunkDebugDrawFlushRenderer(void);

// Save the current contents of the renderer.
void ChipmunkDebugDrawPushRenderer(void);
// Reset the renderer back to it's last pushed state.
void ChipmunkDebugDrawPopRenderer(void);
