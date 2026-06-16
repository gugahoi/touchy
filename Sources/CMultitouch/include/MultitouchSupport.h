#ifndef CMULTITOUCH_MULTITOUCHSUPPORT_H
#define CMULTITOUCH_MULTITOUCHSUPPORT_H

#include <CoreFoundation/CoreFoundation.h>

// Community-standard reverse-engineered layout of Apple's private
// MultitouchSupport.framework. Field layout is load-bearing — do not reorder.

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;

typedef struct {
    int frame;              // frame number
    double timestamp;       // event timestamp
    int identifier;         // persistent finger id while it stays on the pad
    int state;              // touch phase
    int fingerId;
    int handId;
    MTVector normalizedVector; // position + velocity, normalized to [0,1]
    float size;             // total area / pressure proxy
    int zero1;
    float angle;            // ellipse orientation
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector; // position + velocity in mm
    int zero2;
    int zero3;
    float zDensity;         // pressure density
} Finger;

typedef void *MTDeviceRef;

// Callback fires once per multitouch frame with the full set of active fingers.
typedef int (*MTContactCallbackFunction)(MTDeviceRef device,
                                         Finger *fingers,
                                         int numFingers,
                                         double timestamp,
                                         int frame);

MTDeviceRef MTDeviceCreateDefault(void);
CFArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void MTUnregisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void MTDeviceStart(MTDeviceRef device, int unknown);
void MTDeviceStop(MTDeviceRef device);
bool MTDeviceIsRunning(MTDeviceRef device);

#endif /* CMULTITOUCH_MULTITOUCHSUPPORT_H */
