#include <CoreImage/CoreImage.h>
using namespace metal;

// Core Image working space: extended-range linear sRGB (D65). Looks are rendered in
// linear Display P3 primaries and handed back in the working space.

// ---- Color space helpers ----
float3 toP3(float3 rgb) {
    return float3(dot(rgb,float3(.8224619687,.1775380313,0.0)),
                  dot(rgb,float3(.0331941989,.9668058011,0.0)),
                  dot(rgb,float3(.0170826307,.0723974407,.9105199286)));
}
float3 fromP3(float3 p) {
    return float3(dot(p,float3(1.2249401763,-.2249401763,0.0)),
                  dot(p,float3(-.0420569547,1.0420569547,0.0)),
                  dot(p,float3(-.0196375546,-.0786360456,1.0982736001)));
}
float lumaP3(float3 p) { return dot(p,float3(.2289746,.6917385,.0792869)); }
float lumaSRGB(float3 rgb) { return dot(rgb,float3(.2126,.7152,.0722)); }

// Björn Ottosson's OKLab (from linear sRGB).
float3 toLab(float3 rgb) {
    float3 lms = float3(dot(rgb,float3(.4122214708,.5363325363,.0514459929)),
                       dot(rgb,float3(.2119034982,.6806995451,.1073969566)),
                       dot(rgb,float3(.0883024619,.2817188376,.6299787005)));
    lms = sign(lms) * pow(abs(lms),float3(1.0/3.0));
    return float3(dot(lms,float3(.2104542553,.7936177850,-.0040720468)),
                  dot(lms,float3(1.9779984951,-2.4285922050,.4505937099)),
                  dot(lms,float3(.0259040371,.7827717662,-.8086757660)));
}
float3 fromLab(float3 lab) {
    float3 lms = float3(lab.x+.3963377774*lab.y+.2158037573*lab.z,
                       lab.x-.1055613458*lab.y-.0638541728*lab.z,
                       lab.x-.0894841775*lab.y-1.2914855480*lab.z);
    lms = lms*lms*lms;
    return float3(dot(lms,float3(4.0767416621,-3.3077115913,.2309699292)),
                  dot(lms,float3(-1.2684380046,2.6097574011,-.3413193965)),
                  dot(lms,float3(-.0041960863,-.7034186147,1.7076147010)));
}
bool insideP3(float3 rgb) { float3 p=toP3(rgb); return all(p>=-1e-5) && all(p<=1.00001); }
float boundaryChroma(float L, float2 axis) {
    float lo=0, hi=.5;
    for(int i=0;i<16;i++) { float t=(lo+hi)*.5; if(insideP3(fromLab(float3(L,axis*t)))) lo=t; else hi=t; }
    return lo;
}
// Power compression after the ACES Reference Gamut Compression spec (CC BY 4.0),
// applied to OKLab chroma relative to the P3 boundary at constant lightness and hue.
float compressDistance(float d, float threshold, float limit, float power) {
    if (d<threshold) return d;
    float s=(limit-threshold)/pow(pow((1.0-threshold)/(limit-threshold),-power)-1.0,1.0/power);
    float n=(d-threshold)/s;
    return threshold+s*n/pow(1.0+pow(n,power),1.0/power);
}
float3 fitP3(float3 rgb) {
    float3 lab=toLab(rgb);
    lab.x=clamp(lab.x,0.0,1.0);
    float C=length(lab.yz);
    if (C<1e-6) return float3(lab.x*lab.x*lab.x);
    float2 axis=lab.yz/C;
    float Cb=boundaryChroma(lab.x,axis);
    float d=compressDistance(C/max(Cb,1e-6),.85,1.35,1.2);
    float3 p=clamp(toP3(fromLab(float3(lab.x,axis*min(d,1.0)*Cb))),0.0,1.0);
    return fromP3(p);
}

// ---- Photochemical film system (see FilmModel.swift; equations must match) ----
// m0..m2: layer sensitivity rows. neg = (gammaR, gammaG, gammaB, range).
// negOff = (offset R, G, B log10, exposure EV). prt = (gammaR, gammaG, gammaB, range).
// misc = (paper dmin, Richards shape, saturation, highlight chroma retention).
// lights = printer lights (log10).
// d0..d2: print dye cross-absorption rows.
float logistic(float x) { return 1.0/(1.0+exp(-x)); }

float3 filmRender(float3 p, float3 m0, float3 m1, float3 m2, float4 neg, float4 negOff,
                  float4 prt, float4 misc, float3 lights, float3 d0, float3 d1, float3 d2) {
    p*=exp2(negOff.w);
    float Y=lumaP3(p);
    p=Y+(p-Y)*misc.z;
    float3 E=max(float3(dot(m0,p),dot(m1,p),dot(m2,p)),float3(1e-7));
    float3 logE=log10(E/0.18);
    float3 kn=4.0*neg.xyz/neg.w;
    float3 dNeg=neg.w*float3(logistic(kn.x*(logE.x-negOff.x)),logistic(kn.y*(logE.y-negOff.y)),logistic(kn.z*(logE.z-negOff.z)));
    float3 logP=lights-dNeg;
    float3 kp=4.0*prt.xyz/prt.w;
    float3 dP=misc.x+prt.w*pow(float3(logistic(kp.x*logP.x),logistic(kp.y*logP.y),logistic(kp.z*logP.z)),float3(1.0/misc.y));
    float3 dPrint=float3(dot(d0,dP),dot(d1,dP),dot(d2,dP));
    float3 paper=float3(dot(d0,float3(misc.x)),dot(d1,float3(misc.x)),dot(d2,float3(misc.x)));
    return exp10(-(dPrint-paper));
}

// Scene light (working space) → displayed print (working space), soft-mapped into P3.
extern "C" float4 filmSystem(coreimage::sample_t sample, float4 m0, float4 m1, float4 m2,
                             float4 neg, float4 negOff, float4 prt, float4 misc, float4 lights,
                             float4 d0, float4 d1, float4 d2) {
    float a=sample.a;
    float3 p=toP3(sample.rgb/max(a,1e-6));
    float3 o=filmRender(p,m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,misc,lights.xyz,d0.xyz,d1.xyz,d2.xyz);
    // Highlight chroma retention (misc.w): blend bright saturated light toward a
    // ratio-preserving rendering through the same neutral response (see FilmModel).
    float3 q=p*exp2(negOff.w); float Yq=lumaP3(q); q=Yq+(q-Yq)*misc.z;
    float m=max(max(q.x,q.y),max(q.z,1e-7));
    float w=misc.w*smoothstep(1.5,4.0,log2(m/0.18));
    if(w>0.0) {
        // Neutral of brightness m: undo the exposure filmRender re-applies, no saturation.
        float g=filmRender(float3(m)*exp2(-negOff.w),m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,float4(misc.x,misc.y,1.0,0.0),lights.xyz,d0.xyz,d1.xyz,d2.xyz).y;
        o=mix(o,q*(g/m),w);
    }
    return float4(fitP3(fromP3(o))*a,a);
}

// Display-referred photo → scene light: invert the system's neutral response per channel
// (bisection in log exposure), so a JPEG/HEIC is re-rendered by the same film rather than
// having film stacked on top of Apple's rendering.
extern "C" float4 displayToScene(coreimage::sample_t sample, float4 m0, float4 m1, float4 m2,
                                 float4 neg, float4 negOff, float4 prt, float4 misc, float4 lights,
                                 float4 d0, float4 d1, float4 d2) {
    float a=sample.a;
    float3 target=clamp(toP3(sample.rgb/max(a,1e-6)),0.0,1.0);
    float3 lo=float3(-16.0), hi=float3(12.0);
    for(int i=0;i<26;i++) {
        float3 mid=(lo+hi)*.5;
        float3 o=float3(filmRender(float3(0.18*exp2(mid.x)),m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,misc,lights.xyz,d0.xyz,d1.xyz,d2.xyz).y,
                        filmRender(float3(0.18*exp2(mid.y)),m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,misc,lights.xyz,d0.xyz,d1.xyz,d2.xyz).y,
                        filmRender(float3(0.18*exp2(mid.z)),m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,misc,lights.xyz,d0.xyz,d1.xyz,d2.xyz).y);
        lo=select(lo,mid,o<target); hi=select(mid,hi,o<target);
    }
    float3 v=0.18*exp2((lo+hi)*.5);
    v=select(v,float3(0.0),target<=0.0);
    return float4(fromP3(v)*a,a);
}

// ---- Input transforms: camera log / display encodings → working-space light ----
// Code values arrive untouched (the source image is created without color matching).
// Constants: manufacturers' white papers (see ColorSpaces.swift, which mirrors this).
float decodeCurve(float v, int curve) {
    switch (curve) {
    case 1: { // Apple Log
        float r0=-0.05641088, sigma=47.28711236, beta=0.00964052, gamma=0.08550479, delta=0.69336945;
        float pt=sigma*(0.01-r0)*(0.01-r0);
        if (v>=pt) return exp2((v-delta)/gamma)-beta;
        return v>=0.0 ? sqrt(v/sigma)+r0 : r0; }
    case 2: // Sony S-Log3
        return v>=171.2102946929/1023.0 ? exp10((1023.0*v-420.0)/261.5)*0.19-0.01
                                         : (1023.0*v-95.0)*0.01125/(171.2102946929-95.0);
    case 3: // ARRI LogC3 EI 800
        return v>0.149658 ? (exp10((v-0.385537)/0.247190)-0.052272)/5.555556 : (v-0.092809)/5.367655;
    case 4: { // ARRI LogC4
        float a=(262144.0-16.0)/117.45, b=(1023.0-95.0)/1023.0, c=95.0/1023.0;
        float s=(7.0*log(2.0)*exp2(7.0-14.0*c/b))/(a*b), t=(exp2(14.0*(-c/b)+6.0)-64.0)/a;
        return v>=0.0 ? (exp2(14.0*((v-c)/b)+6.0)-64.0)/a : v*s+t; }
    case 5: // Panasonic V-Log
        return v<0.181 ? (v-0.125)/5.6 : exp10((v-0.598206)/0.241514)-0.00873;
    case 6: // DaVinci Intermediate
        return v>0.02740668 ? exp2(v/0.07329248-7.0)-0.0075 : v/10.44426855;
    case 7: // ACEScct
        return v<=0.155251141552511 ? (v-0.0729055341958355)/10.5402377416545 : min(exp2(v*17.52-9.72),65504.0);
    case 8: { // BT.2100 HLG inverse OETF, scaled so 38% signal = 18% gray (BT.2408);
              // sub-black signals mirror (odd extension) so the curve stays monotonic
        float a=0.17883277, b=0.28466892, c=0.55991073, sceneScale=0.18/(0.38*0.38/3.0);
        float e=v<=0.5 ? v*abs(v)/3.0 : (exp((v-c)/a)+b)/12.0;
        return e*sceneScale; }
    case 9: return pow(max(v,0.0),2.4);
    case 10: return v<=0.04045 ? v/12.92 : pow((v+0.055)/1.055,2.4);
    default: return v;
    }
}
extern "C" float4 inputTransform(coreimage::sample_t s, float curve, float4 m0, float4 m1, float4 m2) {
    int c=int(curve+0.5);
    float3 v=float3(decodeCurve(s.r,c),decodeCurve(s.g,c),decodeCurve(s.b,c));
    return float4(dot(m0.xyz,v),dot(m1.xyz,v),dot(m2.xyz,v),1.0);
}

// ---- Halation ----
// Scene highlights above `threshold` (linear luminance) expose through the base and back
// into the red-sensitive layer: the excess, tinted red-orange, is blurred and added back.
extern "C" float4 halationSource(coreimage::sample_t sample, float threshold) {
    float Y=max(lumaSRGB(sample.rgb/max(sample.a,1e-6)),0.0);
    float e=max(Y-threshold,0.0)/(1.0+max(Y-threshold,0.0)*.25);
    return float4(e*float3(1.0,.32,.10),1.0);
}
extern "C" float4 halationAdd(coreimage::sample_t sample, coreimage::sample_t glow, float strength) {
    return float4(sample.rgb+glow.rgb*strength*sample.a,sample.a);
}

// ---- Grain ----
// The seed enters through irrational multiples, so seeds that differ by whole numbers
// (which fract() alone would cancel) still give independent patterns.
float hash(float2 p, float seed) {
    float3 q=fract(float3(p.xyx)*float3(.1031,.1030,.0973)+fract(seed*float3(.6180339887,.7548776662,.5698402910)));
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z)*2.0-1.0;
}
float valueNoise(float2 p, float seed) {
    float2 i=floor(p), f=fract(p);
    float2 u=f*f*(3.0-2.0*f);
    float a=hash(i,seed), b=hash(i+float2(1,0),seed), c=hash(i+float2(0,1),seed), d=hash(i+float2(1,1),seed);
    return mix(mix(a,b,u.x),mix(c,d,u.x),u.y);
}
// Film grain as density noise on perceptual lightness, strongest in the midtones.
// `params` = (amount, cell size in pixels, seed, amplitude correction for sub-pixel cells).
// Below one pixel per cell, the amplitude is reduced to what averaging would produce, so a
// small preview and the full-resolution export carry statistically matching grain.
extern "C" float4 grain(coreimage::sample_t sample, float4 params, coreimage::destination dest) {
    float a=sample.a;
    float3 rgb=sample.rgb/max(a,1e-6);
    float Y=max(lumaSRGB(rgb),0.0);
    float L=pow(Y,1.0/3.0);
    float2 p=dest.coord()/max(params.y,1e-3);
    float n=(valueNoise(p,params.z)+.5*valueNoise(p*2.03+17.0,params.z+1.7))*1.9;
    float envelope=smoothstep(.03,.30,L)*(1.0-smoothstep(.72,1.0,L));
    float Ln=max(L+params.x*.045*params.w*n*envelope,0.0);
    float ratio=Y>1e-7 ? pow(Ln/max(L,1e-4),3.0) : 1.0;
    float3 chroma=float3(valueNoise(p+41.0,params.z),valueNoise(p+83.0,params.z),valueNoise(p+127.0,params.z));
    rgb=rgb*ratio*(1.0+params.x*.012*params.w*chroma*envelope);
    return float4(rgb*a,a);
}

// ---- Local tone (Highlights / Shadows), carried over from the GradingCore study ----
extern "C" float4 lightnessGuide(coreimage::sample_t s) {
    float3 rgb=s.rgb/max(s.a,1e-6);
    float L=pow(max(lumaSRGB(rgb),0.0),1.0/3.0);
    return float4(L,L,L,1);
}
// curve = (kShadow, pivotShadow, kHighlight, pivotHighlight); highlights/shadows in −1…1.
// Positive shadows lift, negative deepen; positive highlights pull down, negative brighten.
extern "C" float4 localTone(coreimage::sample_t s, coreimage::sample_t base,
                            float shadows, float highlights, float4 curve) {
    float3 rgb=s.rgb/max(s.a,1e-6);
    float Y=max(lumaSRGB(rgb),0.0);
    float Lp=pow(Y,1.0/3.0), Lb=clamp(base.r,0.0,1.0);
    float u=clamp(1.0-Lb/curve.y,0.0,1.0);
    float lift=shadows*curve.x*Lb*u*u;
    float y=1.0-Lb, v=clamp(1.0-y/curve.w,0.0,1.0);
    float pull=highlights*curve.z*y*v*v;
    float L=Lp+lift*(1.0-smoothstep(.60,1.0,Lp))-pull*smoothstep(.05,.35,Lp);
    float ratio=pow(max(L,0.0)/max(Lp,.02),3.0);
    return float4(rgb*ratio*s.a,s.a);
}
