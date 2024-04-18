#import bevy_pbr::{
    mesh_types::Mesh, 
    mesh_functions,
    mesh_view_bindings::view,
    view_transformations::position_clip_to_world,
}
#import bevy_voxel_engine::common::{
    VoxelUniforms,
    VOXELS_PER_METER,
}

struct VoxelizationUniforms {
    material: u32,
    flags: u32,
}

@group(2) @binding(0) var<uniform> voxel_uniforms: VoxelUniforms;
@group(2) @binding(1) var voxel_world: texture_storage_3d<r16uint, read_write>;
@group(2) @binding(2) var<storage, read> gh: array<u32>;

@group(3) @binding(0) var<uniform> voxelization_uniforms: VoxelizationUniforms;
@group(3) @binding(1) var material_texture: texture_2d<f32>;
@group(3) @binding(2) var material_sampler: sampler;

struct Vertex {
    @builtin(instance_index) instance_index: u32,
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vertex(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;
    
    var model = mesh_functions::get_model_matrix(vertex.instance_index);
    out.pos = mesh_functions::mesh_position_local_to_clip(model, vec4<f32>(vertex.position, 1.0));

    out.uv = vertex.uv;
    
    return out;
}

fn get_texture_value(pos: vec3<i32>) -> vec2<u32> {
    let texture_value = textureLoad(voxel_world, pos.zyx).r;

    return vec2(
        texture_value & 0xFFu,
        texture_value >> 8u,
    );
}

fn write_pos(pos: vec3<i32>, material: u32, flags: u32) {
    let voxel_type = get_texture_value(pos);

    if (voxel_type.x == 0u) {
        textureStore(voxel_world, pos.zyx, vec4(material | (flags << 8u)));
    }
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let clip_space_xy = vec2(1.0, -1.0) * (2.0 * in.pos.xy / f32(voxel_uniforms.texture_size) - 1.0);
    let clip_space = vec4(clip_space_xy, in.pos.z, 1.0);
    let world = position_clip_to_world(clip_space);
    let texture_pos = VOXELS_PER_METER * world + vec3(f32(voxel_uniforms.texture_size) / 2.0);
    let texture_value = textureSample(material_texture, material_sampler, vec2(in.uv.xy));

    var material = 0u;
    if voxelization_uniforms.material == 255u {
        material = max(u32(texture_value.r * 255.0), 1u);
    } else {
        material = voxelization_uniforms.material;
    }

    write_pos(vec3<i32>(texture_pos), material, voxelization_uniforms.flags);

    let color = voxel_uniforms.materials[material].rgb;
    
    return vec4<f32>(color, 1.0);
}