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
// Kernel-argument ABI (packed by FilmModel+Kernel.swift):
// m0..m2: layer sensitivity rows. neg = (gammaR, gammaG, gammaB, range).
// negOff = (offset R, G, B log10, exposure EV). prt = (gammaR, gammaG, gammaB, range).
// misc = (paper dmin, Richards shape, saturation, highlight chroma retention).
// lights = printer lights (log10): calibrated plus the user's.
// d0..d2: print dye cross-absorption rows.
// Display-referred kernels add ends = soft ends (kneeHigh, a, kneeLow, b) (see SoftEnds in
// FilmModel+Display.swift); displayToScene adds i0..i2, the rows of the inverse sensitivity;
// filmSystemRelative adds baseLights = the calibrated printer lights alone.
// Halation and grain (filmSystem, filmSystemRelative): the scene sampler is followed by `glow`
// (halationMix: rgb = the glow G per layer R, G, B, before the exposure control) and `noise`
// (grainNoise: rgb = unit-variance noise per layer). After the film arguments come k = returned
// light per layer (red, green, blue) and i0..i2 = rows of the inverse sensitivity (both packed by
// Halation.swift), then g0..g7 = one grain table knot each (packed by Grain.swift): (σ red,
// σ green, σ blue, log10 exposure vs mid-gray), σ = density standard deviation per pixel
// (datasheet σ at 48 µm × amount × Selwyn scale), knots ascending.
float logistic(float x) { return 1.0/(1.0+exp(-x)); }

// Layer exposure (rgb = red, green, blue layer) of linear P3 light p, unclamped.
float3 layerExposure(float3 p, float3 m0, float3 m1, float3 m2) { return float3(dot(m0,p),dot(m1,p),dot(m2,p)); }
// The Color control: saturation s about P3 luminance. Linear in p, so it commutes with blurring.
float3 saturated(float3 p, float s) { float Y=lumaP3(p); return Y+(p-Y)*s; }
// log10 of layer exposure E relative to mid-gray.
float3 logExposure(float3 E) { return log10(max(E,float3(1e-7))/0.18); }
// Layer exposure with its halation: E′ = (E + k·glow)/(1 + k) (Halation.exposureWithHalation).
float3 exposureWithHalation(float3 E, float3 glow, float3 k) { return (E+k*glow)/(1.0+k); }

// What the layers receive from scene light p (linear P3): logE, their log exposure with halation,
// and q, the light they see (after the exposure control and saturation) with the halation's change
// of layer exposure carried back through the inverse sensitivity i0..i2 (q feeds highlight chroma
// retention). The glow G was computed without the exposure control (halationSource), so it is
// scaled by 2^EV here; negative lobes are clamped. With k = 0 the glow drops out exactly.
struct LayerExposure { float3 q; float3 logE; };
LayerExposure exposeLayers(float3 p, float3 glow, float3 k, float3 i0, float3 i1, float3 i2,
                           float3 m0, float3 m1, float3 m2, float4 negOff, float4 misc) {
    float3 q=saturated(p*exp2(negOff.w),misc.z);
    float3 E=max(layerExposure(q,m0,m1,m2),0.0);
    float3 halated=exposureWithHalation(E,max(glow,0.0)*exp2(negOff.w),k);
    float3 dE=halated-E;
    return {q+float3(dot(i0,dE),dot(i1,dE),dot(i2,dE)),logExposure(halated)};
}

struct GrainTable { float4 g[8]; };
// Per-layer density standard deviation at log exposure logE: piecewise linear through the 8 knots,
// held at the end values outside them (seven fixed segments, no search).
float3 grainSigma(float3 logE, GrainTable t) {
    float3 s=t.g[0].xyz;
    for(int i=0;i<7;i++) s+=(t.g[i+1].xyz-t.g[i].xyz)*clamp((logE-t.g[i].w)/(t.g[i+1].w-t.g[i].w),0.0,1.0);
    return s;
}

// Layer log exposure → displayed print (display-linear P3); grain = density added to the negative
// layers (R, G, B) before printing.
float3 filmRender(float3 logE, float4 neg, float4 negOff, float4 prt, float4 misc, float3 lights,
                  float3 d0, float3 d1, float3 d2, float3 grain) {
    float3 kn=4.0*neg.xyz/neg.w;
    float3 dNeg=neg.w*float3(logistic(kn.x*(logE.x-negOff.x)),logistic(kn.y*(logE.y-negOff.y)),logistic(kn.z*(logE.z-negOff.z)))+grain;
    float3 logP=lights-dNeg;
    float3 kp=4.0*prt.xyz/prt.w;
    float3 dP=misc.x+prt.w*pow(float3(logistic(kp.x*logP.x),logistic(kp.y*logP.y),logistic(kp.z*logP.z)),float3(1.0/misc.y));
    float3 dPrint=float3(dot(d0,dP),dot(d1,dP),dot(d2,dP));
    float3 paper=float3(dot(d0,float3(misc.x)),dot(d1,float3(misc.x)),dot(d2,float3(misc.x)));
    return exp10(-(dPrint-paper));
}

// q (the light the layers see) and logE (their log exposure, see exposeLayers) → displayed print
// (display-linear P3) before the gamut fit: filmRender plus highlight chroma retention (misc.w),
// which blends bright saturated light toward a ratio-preserving rendering through the same neutral
// response (see FilmModel.render). The neutral response carries the same grain density.
float3 filmPrint(float3 q, float3 logE, float3 m0, float3 m1, float3 m2, float4 neg, float4 negOff,
                 float4 prt, float4 misc, float3 lights, float3 d0, float3 d1, float3 d2, float3 grain) {
    float3 o=filmRender(logE,neg,negOff,prt,misc,lights,d0,d1,d2,grain);
    float m=max(max(q.x,q.y),max(q.z,1e-7));
    float w=misc.w*smoothstep(1.5,4.0,log2(m/0.18));
    if(w>0.0) {
        float g=filmRender(logExposure(layerExposure(float3(m),m0,m1,m2)),neg,negOff,prt,misc,lights,d0,d1,d2,grain).y;
        o=mix(o,q*(g/m),w);
    }
    return o;
}

// Scene light (working space, premultiplied), the halation glow and grain noise → displayed print
// (working space), soft-mapped into P3.
extern "C" float4 filmSystem(coreimage::sample_t sample, coreimage::sample_t glow, coreimage::sample_t noise,
                             float4 m0, float4 m1, float4 m2, float4 neg, float4 negOff, float4 prt, float4 misc, float4 lights,
                             float4 d0, float4 d1, float4 d2, float4 k, float4 i0, float4 i1, float4 i2,
                             float4 g0, float4 g1, float4 g2, float4 g3, float4 g4, float4 g5, float4 g6, float4 g7) {
    float a=sample.a;
    float3 p=toP3(sample.rgb/max(a,1e-6));
    GrainTable t={{g0,g1,g2,g3,g4,g5,g6,g7}};
    LayerExposure x=exposeLayers(p,glow.rgb,k.xyz,i0.xyz,i1.xyz,i2.xyz,m0.xyz,m1.xyz,m2.xyz,negOff,misc);
    float3 o=filmPrint(x.q,x.logE,m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,misc,lights.xyz,d0.xyz,d1.xyz,d2.xyz,grainSigma(x.logE,t)*noise.rgb);
    return float4(fitP3(fromP3(o))*a,a);
}

// ---- Display-referred sources (see FilmModel+Display.swift; equations must match) ----
// Display white and black are given a finite scene estimate (FilmLook constants, mirrored here
// for the bisection bracket): engineering choices, not measurements.
constant float displayCeilingStops=4.0;
constant float displayFloorStops=-9.0;
constant float displaySearchMarginStops=0.5;
constant int displaySearchSteps=22;

// F_n: display-linear green of the calibrated print of a neutral scene `linear`, at zero edits.
float neutralPrint(float linear, float3 m0, float3 m1, float3 m2, float4 neg, float4 negOff,
                   float4 prt, float4 misc, float3 lights, float3 d0, float3 d1, float3 d2) {
    return filmRender(logExposure(layerExposure(float3(linear),m0,m1,m2)),neg,negOff,prt,misc,lights,d0,d1,d2,float3(0.0)).y;
}
// F_n of each component: three neutral scenes, one per channel.
float3 neutralPrint3(float3 v, float3 m0, float3 m1, float3 m2, float4 neg, float4 negOff,
                     float4 prt, float4 misc, float3 lights, float3 d0, float3 d1, float3 d2) {
    return float3(neutralPrint(v.x,m0,m1,m2,neg,negOff,prt,misc,lights,d0,d1,d2),
                  neutralPrint(v.y,m0,m1,m2,neg,negOff,prt,misc,lights,d0,d1,d2),
                  neutralPrint(v.z,m0,m1,m2,neg,negOff,prt,misc,lights,d0,d1,d2));
}
// Soft ends K: identity between the knees, compressing display values toward the print's
// reachable range [F_n(floor), F_n(ceiling)]; `expand` is the closed-form inverse on that range.
float compressEnds(float y, float4 ends) {
    if(y>ends.x) { float u=y-ends.x; return ends.x+u/(1.0+ends.y*u); }
    if(y<ends.z) { float u=ends.z-y; return ends.z-u/(1.0+ends.w*u); }
    return y;
}
float expandEnds(float v, float4 ends) {
    if(v>ends.x) { float u=v-ends.x; return ends.x+u/(1.0-ends.y*u); }
    if(v<ends.z) { float u=ends.z-v; return ends.z-u/(1.0-ends.w*u); }
    return v;
}
float3 compressEnds3(float3 y, float4 ends) { return float3(compressEnds(y.x,ends),compressEnds(y.y,ends),compressEnds(y.z,ends)); }
float3 expandEnds3(float3 v, float4 ends) { return float3(expandEnds(v.x,ends),expandEnds(v.y,ends),expandEnds(v.z,ends)); }

// Display-referred photo (display-linear, working space, premultiplied) → scene estimate (linear,
// working space, premultiplied). Per channel, bisection finds the neutral exposure v whose print
// equals the soft-ended display value; the layers are then given exactly v (s = sensitivity⁻¹·v).
extern "C" float4 displayToScene(coreimage::sample_t sample, float4 m0, float4 m1, float4 m2,
                                 float4 neg, float4 negOff, float4 prt, float4 misc, float4 lights,
                                 float4 d0, float4 d1, float4 d2, float4 ends, float4 i0, float4 i1, float4 i2) {
    float a=sample.a;
    float3 x=clamp(toP3(sample.rgb/max(a,1e-6)),0.0,1.0);
    float3 target=compressEnds3(x,ends);
    float3 lo=float3(displayFloorStops-displaySearchMarginStops), hi=float3(displayCeilingStops+displaySearchMarginStops);
    for(int i=0;i<displaySearchSteps;i++) {
        float3 mid=(lo+hi)*.5;
        float3 o=neutralPrint3(0.18*exp2(mid),m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,misc,lights.xyz,d0.xyz,d1.xyz,d2.xyz);
        lo=select(lo,mid,o<target); hi=select(mid,hi,o<target);
    }
    float3 v=0.18*exp2((lo+hi)*.5);
    float3 s=float3(dot(i0.xyz,v),dot(i1.xyz,v),dot(i2.xyz,v));
    return float4(fromP3(s)*a,a);
}

// Scene estimate of a display-referred photo (linear working space, premultiplied), the halation
// glow and grain noise → displayed print (working space), soft-mapped into P3. The edited print's
// change from the zero-edit print is applied to the original display value, so zero edits
// reproduce the photo up to fitP3 (chroma above 85% of the P3 boundary is compressed); edit
// arguments as filmSystem, plus ends and the calibrated printer lights (baseLights). Halation and
// grain enter the edited print only.
extern "C" float4 filmSystemRelative(coreimage::sample_t sample, coreimage::sample_t glow, coreimage::sample_t noise,
                                     float4 m0, float4 m1, float4 m2,
                                     float4 neg, float4 negOff, float4 prt, float4 misc, float4 lights,
                                     float4 d0, float4 d1, float4 d2, float4 ends, float4 baseLights, float4 k, float4 i0, float4 i1, float4 i2,
                                     float4 g0, float4 g1, float4 g2, float4 g3, float4 g4, float4 g5, float4 g6, float4 g7) {
    float a=sample.a;
    float3 s0=toP3(sample.rgb/max(a,1e-6));
    GrainTable t={{g0,g1,g2,g3,g4,g5,g6,g7}};
    LayerExposure x=exposeLayers(s0,glow.rgb,k.xyz,i0.xyz,i1.xyz,i2.xyz,m0.xyz,m1.xyz,m2.xyz,negOff,misc);
    float3 e=filmPrint(x.q,x.logE,m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,misc,lights.xyz,d0.xyz,d1.xyz,d2.xyz,grainSigma(x.logE,t)*noise.rgb);
    float3 E=max(layerExposure(s0,m0.xyz,m1.xyz,m2.xyz),float3(1e-7));
    float3 b=filmPrint(s0,logExposure(E),m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,misc,baseLights.xyz,d0.xyz,d1.xyz,d2.xyz,float3(0.0));
    // Clamped to what the soft ends produce for display 0…1, so the inverse stays in 0…1.
    float lo=compressEnds(0.0,ends), hi=compressEnds(1.0,ends);
    float3 photo=expandEnds3(clamp(neutralPrint3(E,m0.xyz,m1.xyz,m2.xyz,neg,negOff,prt,misc,baseLights.xyz,d0.xyz,d1.xyz,d2.xyz),lo,hi),ends);
    float3 g=photo/max(b,float3(1e-6));
    // The ratio g carries the photo's offset from its print. Where g < 1 a brightening edit adds
    // (1−g)² of the print's increase on top, so a zero channel can still rise (desaturation) while
    // the slope stays continuous through zero edits.
    float3 out=e*g+select(float3(0.0),(1.0-g)*(1.0-g)*max(e-b,0.0),g<1.0);
    return float4(fitP3(fromP3(out))*a,a);
}

// ---- Input transforms: camera log / display encodings → working-space light ----
// Code values arrive untouched (the source image is created without color matching). Each curve
// below takes its formula's own input: 10-bit legal code / 1023 for S-Log3, LogC3 and V-Log, the
// BT.2100 signal E′ for the rest (see InputColorSpace.formulaTakesCodeValues).
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
    case 9: return sign(v)*pow(abs(v),2.4); // odd extension below 0 (sub-black policy, ENGINE.md)
    case 10: return v<=0.04045 ? v/12.92 : pow((v+0.055)/1.055,2.4);
    default: return v;
    }
}
// Samples → working-space scene light. Each row maps (sample 1, 2, 3, 1) to one channel's curve
// input; Swift folds the signal range, the Y′CbCr matrix and the curve's code-value re-coding
// into these rows once per clip (see CurveInputTransform in VideoSignal.swift).
float3 samplesToWorking(float4 p, float4 r0, float4 r1, float4 r2, float curve, float4 m0, float4 m1, float4 m2) {
    int c=int(curve+0.5);
    float3 v=float3(decodeCurve(dot(r0,p),c),decodeCurve(dot(r1,p),c),decodeCurve(dot(r2,p),c));
    return float3(dot(m0.xyz,v),dot(m1.xyz,v),dot(m2.xyz,v));
}
// R′G′B′ code values (no color matching, alpha ignored) → working-space scene light, opaque.
extern "C" float4 inputTransform(coreimage::sample_t s, float4 r0, float4 r1, float4 r2, float curve,
                                 float4 m0, float4 m1, float4 m2) {
    return float4(samplesToWorking(float4(s.rgb,1.0),r0,r1,r2,curve,m0,m1,m2),1.0);
}
// Y′ and CbCr planes (chroma already upsampled onto the luma grid) → working-space scene light, opaque.
extern "C" float4 ycbcrInputTransform(coreimage::sample_t luma, coreimage::sample_t chroma, float4 r0, float4 r1, float4 r2,
                                      float curve, float4 m0, float4 m1, float4 m2) {
    return float4(samplesToWorking(float4(luma.r,chroma.r,chroma.g,1.0),r0,r1,r2,curve,m0,m1,m2),1.0);
}

// ---- Halation (see Halation.swift; equations must match) ----
// Light re-exposing the emulsion from behind after reflecting at the back of the base; linear in
// exposure. The film kernels add the glow to the layer exposure (exposeLayers).

// Scene light (working space, premultiplied) → layer exposure E = max(sensitivity·saturated(p), 0)
// (rgb = red, green, blue layer), opaque: the film kernels' layer exposure without the exposure
// control. The renderer blurs it with each of the profile's Gaussians.
extern "C" float4 halationSource(coreimage::sample_t sample, float4 m0, float4 m1, float4 m2, float saturation) {
    float3 p=toP3(sample.rgb/max(sample.a,1e-6));
    return float4(max(layerExposure(saturated(p,saturation),m0.xyz,m1.xyz,m2.xyz),0.0),1.0);
}
// Warp: destination coordinate → the source coordinate reflected at the edges of `extent` (x, y,
// width, height), repeating without end. Pixel centres map to pixel centres (edge pixels are
// mirrored, not repeated), so a uniform field stays uniform up to the border.
extern "C" float2 mirroredEdges(float4 extent, coreimage::destination dest) {
    float2 period=2.0*extent.zw;
    float2 u=dest.coord()-extent.xy;
    float2 m=u-period*floor(u/period);
    return extent.xy+select(m,period-m,m>extent.zw);
}
// The three blurred layer exposures → the glow G = Σ weights_j·blur_j (rgb per layer), opaque.
// Unclamped: one weight is negative, and the film kernels clamp G at 0.
extern "C" float4 halationMix(coreimage::sample_t blur0, coreimage::sample_t blur1, coreimage::sample_t blur2, float4 weights) {
    return float4(weights.x*blur0.rgb+weights.y*blur1.rgb+weights.z*blur2.rgb,1.0);
}

// ---- Grain (see Grain.swift) ----
// The seed enters through irrational multiples, so seeds that differ by whole numbers
// (which fract() alone would cancel) still give independent patterns.
float hash(float2 p, float seed) {
    float3 q=fract(float3(p.xyx)*float3(.1031,.1030,.0973)+fract(seed*float3(.6180339887,.7548776662,.5698402910)));
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z)*2.0-1.0;
}
// Uniform hashes summed per value; their sum, scaled to unit variance, is close to Gaussian
// (excess kurtosis −1.2/4).
constant int grainHashesPerValue=4;
// Hash k (0…11) of a pixel is read at pixel + k·grainDrawOffset (exact in float). The offsets'
// differences are never whole pixels (k − k′ < 32), so no hash is shared with another pixel or
// channel; steps under a pixel this size keep the draws independent (k/16 steps left the sum's
// excess kurtosis at −0.46 instead of −0.30).
constant float2 grainDrawOffset=float2(17.0,9.0)/32.0;
// Generator: rgb = three independent, zero-mean, unit-variance values per integer pixel (red,
// green and blue layer), deterministic for `seed`; opaque. White: no correlation between pixels.
extern "C" float4 grainNoise(float seed, coreimage::destination dest) {
    float2 pixel=floor(dest.coord());
    float3 n=float3(0.0);
    for(int c=0;c<3;c++) {
        for(int k=0;k<grainHashesPerValue;k++) n[c]+=hash(pixel+float(c*grainHashesPerValue+k)*grainDrawOffset,seed);
    }
    // A uniform on [−1, 1) has variance 1/3.
    return float4(n*sqrt(3.0/float(grainHashesPerValue)),1.0);
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
