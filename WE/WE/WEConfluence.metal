#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

float weHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float weNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(weHash(i), weHash(i + float2(1.0, 0.0)), f.x),
        mix(
            weHash(i + float2(0.0, 1.0)),
            weHash(i + float2(1.0, 1.0)),
            f.x
        ),
        f.y
    );
}

float weFBM(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float2x2 turn = float2x2(
        float2(0.80, -0.60),
        float2(0.60, 0.80)
    );

    for (int octave = 0; octave < 4; octave++) {
        value += amplitude * weNoise(p);
        p = turn * p * 2.02 + 17.13;
        amplitude *= 0.5;
    }

    return value;
}

float weSoftField(
    float2 p,
    float2 center,
    float2 scale,
    float rotation,
    float time,
    float seed
) {
    float sine = sin(rotation);
    float cosine = cos(rotation);
    float2 q = p - center;
    q = float2(
        cosine * q.x - sine * q.y,
        sine * q.x + cosine * q.y
    );
    q /= scale;

    float2 warp = float2(
        weFBM(q * 1.55 + float2(seed, time * 0.055)),
        weFBM(q * 1.72 + float2(8.2 + seed, -time * 0.046))
    ) - 0.5;
    q += warp * 0.46;

    float body = exp(-dot(q, q) * 1.55);
    float folds = 0.58 + 0.62 * weFBM(
        q * 2.45 + float2(time * 0.035, seed * 3.1)
    );
    float ribbon = 0.72 + 0.28 * sin(
        q.x * 4.8 - q.y * 3.2 + time * 0.24 + seed
    );

    return body * folds * ribbon;
}

[[ stitchable ]] half4 weConfluence(
    float2 position,
    half4 source,
    float2 size,
    float time,
    half4 personalColor,
    half4 partnerColor,
    float connection
) {
    float shortestSide = max(min(size.x, size.y), 1.0);
    float2 p = (position - size * 0.5) / shortestSide;
    p.x *= size.x / max(size.y, 1.0);

    float breath = 1.0 + sin(time * 0.42) * 0.018;
    p /= breath;

    float progress = saturate(connection);
    float morph = smoothstep(0.18, 0.82, progress);
    float separation = mix(0.205, 0.095, progress);
    float drift = sin(time * 0.31) * 0.018;
    float2 leftCenter = float2(-separation, -0.015 + drift);
    float2 rightCenter = float2(separation, 0.02 - drift);

    float leftSmoke = weSoftField(
        p,
        leftCenter,
        float2(0.27, 0.39),
        -0.36 + sin(time * 0.17) * 0.08,
        time,
        1.7
    );

    float rightSmoke = weSoftField(
        p,
        rightCenter,
        float2(0.27, 0.40),
        0.38 + cos(time * 0.16) * 0.08,
        time,
        6.4
    );

    float circleRadius = 0.128;
    float leftDistance = length(p - leftCenter);
    float rightDistance = length(p - rightCenter);
    float leftCircle = 1.0 - smoothstep(
        circleRadius - 0.007,
        circleRadius + 0.007,
        leftDistance
    );
    float rightCircle = 1.0 - smoothstep(
        circleRadius - 0.007,
        circleRadius + 0.007,
        rightDistance
    );

    float leftSphere = sqrt(
        saturate(1.0 - pow(leftDistance / circleRadius, 2.0))
    );
    float rightSphere = sqrt(
        saturate(1.0 - pow(rightDistance / circleRadius, 2.0))
    );
    leftCircle *= 0.72 + leftSphere * 0.34;
    rightCircle *= 0.72 + rightSphere * 0.34;

    float left = mix(leftCircle, leftSmoke, morph);
    float right = mix(rightCircle, rightSmoke, morph);

    float2 bridgePoint = float2(
        sin(p.y * 6.2 + time * 0.22) * 0.07,
        p.y
    );
    float bridge = exp(
        -pow(abs(p.x - bridgePoint.x) * 6.5, 1.45)
        -pow(abs(p.y) * 2.05, 2.0)
    );
    bridge *= morph * (
        0.42 + 0.42 * weFBM(p * 4.1 + time * 0.035)
    );

    float density = left + right + bridge;
    float alphaCore = smoothstep(0.08, 0.79, density);
    float alphaHalo = smoothstep(0.018, 0.34, density) * 0.30;
    float alpha = max(alphaCore, alphaHalo);

    float personalWeight = left / max(left + right, 0.001);
    float3 personal = float3(personalColor.rgb);
    float3 partner = float3(partnerColor.rgb);
    float3 blended = mix(partner, personal, personalWeight);

    float overlap = saturate(
        min(left, right) * 2.8 + bridge * saturate(connection)
    );
    float foldLight = pow(
        saturate(
            weFBM(p * 5.2 + float2(time * 0.025, -time * 0.018))
        ),
        2.0
    );
    float edgeLight = smoothstep(0.10, 0.62, density)
        - smoothstep(0.62, 1.15, density);
    float leftGlint = exp(
        -dot(
            (p - leftCenter - float2(-0.042, -0.048)) * 19.0,
            (p - leftCenter - float2(-0.042, -0.048)) * 19.0
        )
    );
    float rightGlint = exp(
        -dot(
            (p - rightCenter - float2(-0.042, -0.048)) * 19.0,
            (p - rightCenter - float2(-0.042, -0.048)) * 19.0
        )
    );
    float orbGlint = (leftGlint + rightGlint) * (1.0 - morph);

    blended = mix(blended, (personal + partner) * 0.5, overlap * 0.58);
    blended += float3(0.19, 0.18, 0.16)
        * foldLight
        * alphaCore
        * morph;
    blended += float3(0.30, 0.28, 0.25) * edgeLight * 0.22;
    blended = mix(
        blended,
        float3(0.92, 0.89, 0.83),
        saturate(orbGlint * 0.42)
    );
    blended *= 0.72 + density * 0.42;

    float vignette = 1.0 - smoothstep(0.18, 0.76, length(p));
    alpha *= saturate(vignette * 1.25);

    return half4(half3(blended * alpha), half(alpha));
}
