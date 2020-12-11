uniform sampler2D baseTexture;

uniform vec4 emissiveColor;
uniform vec4 skyBgColor;
uniform float fogDistance;
uniform vec3 eyePosition;

#ifdef ENABLE_DYNAMIC_SHADOWS
//shadow uniforms
uniform mat4 mShadowWorldViewProj0;
uniform mat4 mShadowWorldViewProj1;
uniform mat4 mShadowWorldViewProj2;
uniform vec4 mShadowCsmSplits;
uniform vec3 v_LightDirection;
uniform float f_textureresolution;
uniform float f_brightness;

varying vec3 P;
varying vec3 N;

// shadow texture
uniform sampler2D ShadowMapSampler;
#endif


varying vec3 vNormal;
varying vec3 vPosition;
varying vec3 worldPosition;
varying lowp vec4 varColor;
centroid varying mediump vec2 varTexCoord;

varying vec3 eyeVec;
varying float vIDiff;

const float e = 2.718281828459;
const float BS = 10.0;
const float fogStart = FOG_START;
const float fogShadingParameter = 1.0 / (1.0 - fogStart);



#ifdef ENABLE_DYNAMIC_SHADOWS
	vec2 poissonDisk[4] = vec2[](
	  vec2( -0.94201624, -0.39906216 ),
	  vec2( 0.94558609, -0.76890725 ),
	  vec2( -0.094184101, -0.92938870 ),
	  vec2( 0.34495938, 0.29387760 )
	);
	vec2 offsetArray[16]=vec2[](
		 vec2(0.0, 0.0),
	     vec2(0.0, 1.0),
	     vec2(1.0, 0.0),
	     vec2(1.0, 1.0),
	     vec2(-2.0, 0.0),
	     vec2(0.0, -2.0),
	     vec2(2.0, -2.0),
	     vec2(-2.0, 2.0),
	     vec2(3.0, 0.0),
	     vec2(0.0, 3.0),
	     vec2(3.0, 3.0),
	     vec2(-3.0, -3.0),
	     vec2(-4.0, 0.0),
	     vec2(0.0, -4.0),
	     vec2(4.0, -4.0),
	     vec2(-4.0, 4.0));
	float testShadow(sampler2D shadowsampler, vec2 smTexCoord, float realDistance ,int cIdx) {
	     
		float nsamples=16;
	    float visibility=0.0;
	    
	    for (int i = 0; i < nsamples; i++){
	        vec2 clampedpos = smTexCoord + (offsetArray[i] /vec2(f_textureresolution));
	        //clampedpos=clamp(clampedpos.xy, vec2(0.0, 0.0), vec2(1.0, 1.0));         
	        if ( texture2D( shadowsampler, clampedpos.xy )[cIdx] < realDistance ){
	            visibility += 1.0 / nsamples;
	        }        
	        
	    }
	    
	    return pow(visibility ,2.2);
	}

	float testShadow2(sampler2D shadowsampler, vec2 smTexCoord, float realDistance ,int cIdx) {
	    float texDepth = texture2D(shadowsampler, smTexCoord.xy )[cIdx];
	   
	    return (realDistance > texDepth ) ?  1.0  :0.0 ;
	}
	float smin( float a, float b, float k )
	{
	    float h = max( k-abs(a-b), 0.0 )/k;
	    return max( a, b ) + h*h*k*(1.0/4.0);
	}

#endif

#ifdef ENABLE_TONE_MAPPING

/* Hable's UC2 Tone mapping parameters
	A = 0.22;
	B = 0.30;
	C = 0.10;
	D = 0.20;
	E = 0.01;
	F = 0.30;
	W = 11.2;
	equation used:  ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F
*/

vec3 uncharted2Tonemap(vec3 x)
{
	return ((x * (0.22 * x + 0.03) + 0.002) / (x * (0.22 * x + 0.3) + 0.06)) - 0.03333;
}

vec4 applyToneMapping(vec4 color)
{
	color = vec4(pow(color.rgb, vec3(2.2)), color.a);
	const float gamma = 1.6;
	const float exposureBias = 5.5;
	color.rgb = uncharted2Tonemap(exposureBias * color.rgb);
	// Precalculated white_scale from
	//vec3 whiteScale = 1.0 / uncharted2Tonemap(vec3(W));
	vec3 whiteScale = vec3(1.036015346);
	color.rgb *= whiteScale;
	return vec4(pow(color.rgb, vec3(1.0 / gamma)), color.a);
}
#endif

void main(void)
{
	vec3 color;
	vec2 uv = varTexCoord.st;

	vec4 base = texture2D(baseTexture, uv).rgba;

#ifdef USE_DISCARD
	// If alpha is zero, we can just discard the pixel. This fixes transparency
	// on GPUs like GC7000L, where GL_ALPHA_TEST is not implemented in mesa,
	// and also on GLES 2, where GL_ALPHA_TEST is missing entirely.
	if (base.a == 0.0) {
		discard;
	}
#endif

	color = base.rgb;

	vec4 col = vec4(color.rgb, base.a);

	col.rgb *= varColor.rgb;

	col.rgb *= emissiveColor.rgb * vIDiff;

#ifdef ENABLE_TONE_MAPPING
	col = applyToneMapping(col);
#endif

	// Due to a bug in some (older ?) graphics stacks (possibly in the glsl compiler ?),
	// the fog will only be rendered correctly if the last operation before the
	// clamp() is an addition. Else, the clamp() seems to be ignored.
	// E.g. the following won't work:
	//      float clarity = clamp(fogShadingParameter
	//		* (fogDistance - length(eyeVec)) / fogDistance), 0.0, 1.0);
	// As additions usually come for free following a multiplication, the new formula
	// should be more efficient as well.
	// Note: clarity = (1 - fogginess)
	float clarity = clamp(fogShadingParameter
		- fogShadingParameter * length(eyeVec) / fogDistance, 0.0, 1.0);
	col = mix(skyBgColor, col, clarity);

#ifdef ENABLE_DYNAMIC_SHADOWS
		float shadow_int =0.0;
		vec3 ccol=vec3(0.0);
		float diffuseLight = dot(N,normalize(-v_LightDirection)) ;
	    float bias = max(0.00005 * (1.0 - diffuseLight), 0.000005) ;  
		diffuseLight = clamp(diffuseLight,0.5,1.0);
		float shadow_int0 =0.0;
		float shadow_int1 =0.0;
		float shadow_int2 =0.0;
		
		vec3 posInWorld= gl_TexCoord[3].xyz ;
		float cIdxFloat = float(2.0);
	    for(int i=1;i<3;i++) {
	    	// branchless cascade selector :)!
	        cIdxFloat -= max(sign(mShadowCsmSplits[i] - posInWorld.z), 0.0);
	     }
	     
		vec4 posInShadow= 0.5+0.5*mShadowWorldViewProj2*vec4(P,1.0);
		if(posInShadow.x>=0.0&&posInShadow.x<=1.0&&
			posInShadow.y>=0.0&&posInShadow.y<=1.0)
		shadow_int2=testShadow(ShadowMapSampler, posInShadow.xy, posInShadow.z - bias ,2);
		

		     posInShadow= 0.5+0.5*mShadowWorldViewProj1*vec4(P,1.0);
		if(posInShadow.x>=0.0&&posInShadow.x<=1.0&&
			posInShadow.y>=0.0&&posInShadow.y<=1.0)
		shadow_int1=testShadow(ShadowMapSampler, posInShadow.xy, posInShadow.z - (bias*0.5),1);
		

		     posInShadow= 0.5+0.5*mShadowWorldViewProj0*vec4(P,1.0);
		if(posInShadow.x>=0.0&&posInShadow.x<=1.0&&
			posInShadow.y>=0.0&&posInShadow.y<=1.0)
		shadow_int0=testShadow(ShadowMapSampler, posInShadow.xy, posInShadow.z - (bias*0.25),0);
		

			int cIdx=int(cIdxFloat);
		shadow_int = cIdx==2?shadow_int2:shadow_int1;
		shadow_int = cIdx==0?shadow_int0:shadow_int;
		shadow_int*=0.30;
		//ccol[cIdx]=0.5;

		gl_FragColor = clamp(vec4((col.rgb-shadow_int)*diffuseLight+ccol,base.a),0.0,1.0);
	#else
	gl_FragColor = vec4(col.rgb, base.a);
	#endif
	
}
