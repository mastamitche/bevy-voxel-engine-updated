#import bevy_voxel_engine::common::VoxelUniforms

#import bevy_voxel_engine::bindings::{
    voxel_worlds,
    voxel_uniforms,
    gh
}

struct ComputeUniforms {
    time: f32,
    delta_time: f32,
}

@group(1) @binding(0)
var<uniform> compute_uniforms: ComputeUniforms;
@group(1) @binding(2)
var<storage, read> animation_data: array<u32>;

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

fn write_pos(pos: vec3<i32>, material: u32, flags: u32) {
    let chunk_index = get_chunk_index(vec3<f32>(pos));
    if (chunk_index == -1) {
        return; // Skip if out of bounds
    }
    
    let chunk_pos = pos % vec3(i32(voxel_uniforms.chunk_size));
    let voxel_type = get_texture_value(pos, chunk_index);
    if (voxel_type.x == 0u) {
        textureStore(voxel_worlds[chunk_index], chunk_pos.zyx, vec4<u32>(material | (flags << 8u)));
    }
}

@compute @workgroup_size(1, 1, 1)
fn animation(@builtin(global_invocation_id) invocation_id: vec3<u32>) {
    // Place animation data into world
    let header_len = i32(animation_data[0]);
    let dispatch_size = i32(ceil(pow(f32(header_len), 1.0 / 3.0)));

    let pos = vec3(i32(invocation_id.x), i32(invocation_id.y), i32(invocation_id.z));
    let index = pos.x * dispatch_size * dispatch_size + pos.y * dispatch_size + pos.z + 1;

    if (index <= header_len) {
        let data_index = i32(u32(animation_data[index]) & 0x00FFFFFFu);
        let data_type = i32(u32(animation_data[index]) >> 24u);

        let texture_pos = vec3(
            bitcast<i32>(animation_data[data_index + 0]),
            bitcast<i32>(animation_data[data_index + 1]),
            bitcast<i32>(animation_data[data_index + 2]),
        );
        let material = animation_data[data_index + 3];
        let flags = animation_data[data_index + 4];

        if (data_type == 0) {
            // Particle
            write_pos(texture_pos, material, flags);
        } else if (data_type == 1) {
            // Edges
            let half_size = vec3(
                bitcast<i32>(animation_data[data_index + 5]),
                bitcast<i32>(animation_data[data_index + 6]),
                bitcast<i32>(animation_data[data_index + 7]),
            );

            for (var x = -half_size.x; x <= half_size.x; x++) {
                for (var y = -half_size.y; y <= half_size.y; y++) {
                    for (var z = -half_size.z; z <= half_size.z; z++) {
                        let pos = vec3(x, y, z);
                        if (abs(pos.x) == half_size.x || abs(pos.y) == half_size.y) {
                            if (abs(pos.x) == half_size.x || abs(pos.z) == half_size.z) {
                                if (abs(pos.y) == half_size.y || abs(pos.z) == half_size.z) {
                                    write_pos(texture_pos + pos, material, flags);
                                }
                            }
                        }
                    }
                }
            }
        } else if (data_type == 2) {
            // Boxes
            let half_size = vec3(
                bitcast<i32>(animation_data[data_index + 5]),
                bitcast<i32>(animation_data[data_index + 6]),
                bitcast<i32>(animation_data[data_index + 7]),
            );
            
            for (var x = -half_size.x; x <= half_size.x; x++) {
                for (var y = -half_size.y; y <= half_size.y; y++) {
                    for (var z = -half_size.z; z <= half_size.z; z++) {
                        let pos = vec3(x, y, z);
                        write_pos(texture_pos + pos, material, flags);
                    }
                }
            }
        }
    }
}
