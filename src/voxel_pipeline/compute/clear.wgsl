#import bevy_voxel_engine::common::{
    VoxelUniforms,
    ANIMATION_FLAG,
    PORTAL_FLAG
}

#import bevy_voxel_engine::bindings::{
    voxel_worlds,
    voxel_uniforms,
    gh
}

fn get_chunk_index(world_pos: vec3<f32>) -> i32 {
    let chunk_pos = floor(world_pos / f32(voxel_uniforms.chunk_size));
    for (var i = 0; i < 27; i++) {
        if (all(chunk_pos == vec3<f32>(voxel_uniforms.active_chunks[i].position))) {
            return i32(voxel_uniforms.active_chunks[i].texture_index);
        }
    }
    return -1; // Out of bounds
}

fn get_texture_value(pos: vec3<i32>, chunk_index: i32) -> vec2<u32> {
    let chunk_pos = pos % vec3(i32(voxel_uniforms.chunk_size));
    let texture_value = textureLoad(voxel_worlds[chunk_index], chunk_pos.zyx).r;
    return vec2(
        texture_value & 0xFFu,
        texture_value >> 8u,
    );
}

@compute @workgroup_size(4, 4, 4)
fn clear(@builtin(global_invocation_id) invocation_id: vec3<u32>) {
    let pos = vec3(i32(invocation_id.x), i32(invocation_id.y), i32(invocation_id.z));
    let chunk_index = get_chunk_index(vec3<f32>(pos));
    
    if (chunk_index == -1) {
        return; // Skip if out of bounds
    }

    let material = get_texture_value(pos, chunk_index);

    // Delete old animation data
    if ((material.y & (ANIMATION_FLAG | PORTAL_FLAG)) > 0u) {
        let chunk_pos = pos % vec3(i32(voxel_uniforms.chunk_size));
        textureStore(voxel_worlds[chunk_index], chunk_pos.zyx, vec4<u32>(0u));
        return;
    }
}
