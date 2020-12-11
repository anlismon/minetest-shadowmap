 
uniform sampler2D ShadowMapSampler0;
uniform sampler2D ShadowMapSampler1;
uniform sampler2D ShadowMapSampler2;


void main() {
   
   vec2  depth_split0=texture2D(ShadowMapSampler0, gl_TexCoord[0].xy ).rg ;
   float depth_split1=texture2D(ShadowMapSampler1, gl_TexCoord[1].xy ).r ;
   float depth_split2=texture2D(ShadowMapSampler2, gl_TexCoord[2].xy ).r ;
    
 #ifdef ENABLE_DYNAMIC_SHADOWS_VMS
	gl_FragColor = vec4(depth_split0.x,depth_split1,depth_split2,depth_split0.y);
#else 
	gl_FragColor = vec4(depth_split0.r,depth_split1,depth_split2,1.0);
#endif

}
