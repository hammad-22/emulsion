#include <CoreImage/CoreImage.h>
using namespace metal;

// The digicam process (Renderer+Digicam.swift): a mid-2000s compact CCD camera's in-camera JPEG.
// Not a film process. Pointwise math mirrors DigicamModel.swift; constants arrive as arguments
// from DigicamLook.swift. Working space: extended linear sRGB (D65).
//
// Copied from Emulsion.ci.metal so the film kernels' open PRs merge cleanly: digicamLuma709
// (lumaSRGB), digicamDecode (decodeCurve's sRGB case 10) and its inverse digicamEncode, digicamHash
// (the grain `hash`) and the value-noise lattice (valueNoise).
// Follow-up: share them through a header.

float digicamLuma709(float3 rgb) { return dot(rgb,float3(.2126,.7152,.0722)); }
float3 digicamEncode(float3 x) { return select(1.055*pow(max(x,0.0),1.0/2.4)-0.055, 12.92*x, x<=0.0031308); }
float3 digicamDecode(float3 v) { return select(pow((max(v,0.0)+0.055)/1.055,2.4), v/12.92, v<=0.04045); }

// The seed enters through irrational multiples, so whole-number seeds stay independent.
float digicamHash(float2 p, float seed) {
    float3 q=fract(float3(p.xyx)*float3(.1031,.1030,.0973)+fract(seed*float3(.6180339887,.7548776662,.5698402910)));
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z)*2.0-1.0;
}
// Three independent values per lattice point (digicamHash's seeding, its own mixing), in −1…1.
float3 digicamHash3(float2 p, float seed) {
    float3 q=fract(float3(p.xyx)*float3(.1031,.1030,.0973)+fract(seed*float3(.6180339887,.7548776662,.5698402910)));
    q+=dot(q,q.yxz+33.33);
    return fract((q.xxy+q.yzz)*q.zyx)*2.0-1.0;
}
// Smooth value noise, one lattice for all three channels.
float3 digicamValueNoise3(float2 p, float seed) {
    float2 i=floor(p), f=fract(p);
    float2 u=f*f*(3.0-2.0*f);
    float3 a=digicamHash3(i,seed), b=digicamHash3(i+float2(1,0),seed), c=digicamHash3(i+float2(0,1),seed),
           d=digicamHash3(i+float2(1,1),seed);
    return mix(mix(a,b,u.x),mix(c,d,u.x),u.y);
}

// JPEG tone curve on x = light / clip (0…1, black offset already removed): sRGB encode, a power
// that puts mid-gray on the pivot, an S curve (a square on each side) pivoting there whose slope
// at 1 is 1 − contrast (a hard clip, no shoulder), then lifted to the black floor.
// curve = (pivot, black floor code, -, -).
float digicamToneCurve(float x, float gammaPower, float contrast, float4 curve) {
    float p=curve.x;
    float t=pow(digicamEncode(float3(clamp(x,0.0,1.0))).x,gammaPower);
    float lo=t/p, hi=(1.0-t)/(1.0-p);
    float s=t<p ? p*lo*lo : 1.0-(1.0-p)*hi*hi;
    float v=mix(t,s,contrast);
    return digicamDecode(float3(curve.y+(1.0-curve.y)*v)).x;
}

// Scene light (working space, premultiplied) → near-clip mask (0…1, opaque). `fringe` = (scene
// light that clips at this exposure, onset fraction of it where the mask starts).
extern "C" float4 digicamFringeSource(coreimage::sample_t s, float2 fringe) {
    float3 rgb=s.rgb/max(s.a,1e-6);
    float m=smoothstep(fringe.x*fringe.y,fringe.x,max(rgb.r,max(rgb.g,rgb.b)));
    return float4(m,m,m,1.0);
}

// Scene light (working space, premultiplied), its near-clip mask and the blurred mask → scene light
// with purple fringing (premultiplied): the blur's spill outside the mask, × `fringe` (colour × strength).
extern "C" float4 digicamFringe(coreimage::sample_t s, coreimage::sample_t mask, coreimage::sample_t maskBlur, float4 fringe) {
    return float4(s.rgb+fringe.rgb*max(maskBlur.r-mask.r,0.0)*s.a,s.a);
}

// Scene light (working space, premultiplied, already softened by the lens) and its corner blur → display light
// (display-linear sRGB in 0…1, working space, premultiplied).
// lens = (centre x, centre y, 1 / half-diagonal², vignette stops at the corner).
// gains = (white balance × 2^exposure, clip). noise = (amount, luminance cell px, chroma cell px,
// seed); noiseShape = (shot, read floor, chroma share, blue noise gain). tone = (saturation, gamma power,
// contrast, black offset); curve as digicamToneCurve.
extern "C" float4 digicamCapture(coreimage::sample_t s, coreimage::sample_t soft, float4 lens, float4 gains,
                                 float4 noise, float4 noiseShape, float4 tone, float4 curve,
                                 coreimage::destination dest) {
    float a=s.a;
    float3 rgb=s.rgb/max(a,1e-6);
    float2 c=dest.coord();
    float2 d=c-lens.xy;
    float r2=dot(d,d)*lens.z;
    rgb=mix(rgb,soft.rgb/max(soft.a,1e-6),clamp(r2,0.0,1.0));
    rgb*=exp2(-lens.w*r2)*gains.rgb;
    float clip=gains.w;
    if(noise.x>0.0) {
        float Y=max(digicamLuma709(rgb),0.0);
        float sigma=noise.x*clip*(noiseShape.x*sqrt(Y/clip)+noiseShape.y);
        float lumaCell=max(noise.y,1.0), chromaCell=max(noise.z,1.0);
        float n=digicamHash(floor(c/lumaCell),noise.w)*min(noise.y,1.0);
        float3 chroma=digicamValueNoise3(c/chromaCell,noise.w+3.1)*noiseShape.z*min(noise.z,1.0);
        rgb+=sigma*(n+chroma)*float3(1.0,1.0,noiseShape.w);
    }
    float3 x=max(min(rgb,float3(clip))/clip-tone.w,0.0)/(1.0-tone.w);
    float Yx=digicamLuma709(x);
    x=clamp(Yx+(x-Yx)*tone.x,0.0,1.0);
    float3 o=float3(digicamToneCurve(x.r,tone.y,tone.z,curve),digicamToneCurve(x.g,tone.y,tone.z,curve),
                    digicamToneCurve(x.b,tone.y,tone.z,curve));
    return float4(o*a,a);
}

// Display light (display-linear sRGB, premultiplied) → gamma-encoded luma (opaque), to blur for sharpening.
extern "C" float4 digicamEncodedLuma(coreimage::sample_t s) {
    float Y=digicamLuma709(digicamEncode(s.rgb/max(s.a,1e-6)));
    return float4(Y,Y,Y,1.0);
}

// Display light (display-linear sRGB, premultiplied) and its blurred encoded luma → sharpened display
// light (premultiplied): an unsharp mask on encoded luma, clipped to 0…1, so edges get bright and dark halos.
extern "C" float4 digicamSharpen(coreimage::sample_t s, coreimage::sample_t blurredLuma, float amount) {
    float a=s.a;
    float3 e=digicamEncode(s.rgb/max(a,1e-6));
    float detail=digicamLuma709(e)-blurredLuma.r;
    return float4(digicamDecode(clamp(e+amount*detail,0.0,1.0))*a,a);
}
