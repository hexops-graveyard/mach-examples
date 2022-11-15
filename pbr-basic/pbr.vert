#version 450

layout (location = 0) in vec3 inPos;
layout (location = 1) in vec3 inNormal;

layout (binding = 0) uniform UBO 
{
	mat4 projection;
	mat4 model;
	mat4 view;
	vec3 camPos;
} ubo;

layout (location = 0) out vec3 outWorldPos;
layout (location = 1) out vec3 outNormal;

layout (binding = 3) uniform ObjectParams {
	vec3 objPos;
} object;

out gl_PerVertex 
{
	vec4 gl_Position;
};

void main() 
{
	vec3 locPos = vec3(ubo.model * vec4(inPos, 1.0));
	outWorldPos = locPos + object.objPos;
	outNormal = mat3(ubo.model) * inNormal;
	gl_Position =  ubo.projection * ubo.view * vec4(outWorldPos, 1.0);
}
