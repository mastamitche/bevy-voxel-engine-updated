#import bevy_voxel_engine::common::{
    VoxelUniforms,
    SAND_FLAG,
    AUTOMATA_FLAG,
    ANIMATION_FLAG,
    COLLISION_FLAG,
    hash,
    snoise
}

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
@group(1) @binding(1)
var<storage, read_write> physics_data: array<u32>;

fn get_chunk_index(world_pos: vec3<f32>) -> i32 {
    let chunk_pos = floor(world_pos / f32(voxel_uniforms.chunk_size));
    for (var i = 0; i < 27; i++) {
        if (all(chunk_pos == vec3<f32>(voxel_uniforms.active_chunks[i].position))) {
            return i32(voxel_uniforms.active_chunks[i].texture_index);
        }
    }
    return -1; // Out of bounds
}


fn in_texture_bounds(pos: vec3<i32>) -> bool {
    return all(pos >= vec3(0)) && all(pos < vec3(i32(voxel_uniforms.chunk_size)));
}


fn get_texture_value(pos: vec3<i32>, chunk_index: i32) -> vec2<u32> {
    let texture_value = textureLoad(voxel_worlds[chunk_index], pos.zyx).r;
    return vec2(
        texture_value & 0xFFu,
        texture_value >> 8u,
    );
}

fn write_pos(pos: vec3<i32>, material: u32, flags: u32, chunk_index: i32) {
    let voxel_type = get_texture_value(pos, chunk_index);
    if (voxel_type.x == 0u) {
        textureStore(voxel_worlds[chunk_index], pos.zyx, vec4(material | (flags << 8u)));
    }
}
@compute @workgroup_size(4, 4, 4)
fn automata(@builtin(global_invocation_id) invocation_id: vec3<u32>) {
    let chunk_index = get_chunk_index(vec3<f32>(invocation_id));
    if (chunk_index == -1) {
        return; // Skip if out of bounds
    }

    let pos = vec3(i32(invocation_id.x), i32(invocation_id.y), i32(invocation_id.z)) % vec3(i32(voxel_uniforms.chunk_size));
    let pos_seed = vec3<u32>(pos);
    let pos_time_seed = vec3<u32>(vec3<f32>(pos) + compute_uniforms.time * 240.0);

    let material = get_texture_value(pos, chunk_index);

    // grass
    let pos_rand = hash(pos_seed + 100u);

    if (material.x == 44u && (material.y & ANIMATION_FLAG) == 0u && hash(pos_seed + 50u).x >= 0.5) {
        for (var i = 1; i < 4 + i32(pos_rand.y * 3.0 - 0.5); i += 1) {
            let i = f32(i);

            let offset = vec3(
                3.0 * snoise(vec3<f32>(pos) / 50.0 + compute_uniforms.time * 0.3) - 0.5, 
                i, 
                3.0 * snoise(vec3<f32>(pos) / 50.0 + compute_uniforms.time * 0.3) - 0.5
            );

            let new_pos = vec3<f32>(pos) + vec3(
                ((i - 1.0) / 4.0) * offset.x, 
                offset.y, 
                ((i - 1.0) / 4.0) * offset.z
            );

            let new_chunk_index = get_chunk_index(new_pos);
            if (new_chunk_index != -1) {
                write_pos(vec3<i32>(new_pos) % vec3(i32(voxel_uniforms.chunk_size)), u32(i), ANIMATION_FLAG, new_chunk_index);
            }
        }
    }
    
    let rand = hash(pos_time_seed + 10u);

    /*
    // turn grass to dirt 
    if (material.x == 44u && (material.y & ANIMATION_FLAG) == 0u) {
        let new_mat = get_texture_value(pos + vec3(0, 1, 0));
        if (new_mat.x != 0u && (new_mat.y & ANIMATION_FLAG) == 0u && rand.y < 0.01) {
            textureStore(voxel_worlds, pos.zyx, vec4(43u | (material.y << 8u)));
        }
    }
    */

    /*
    // spread grass
    if (material.x == 44u && (material.y & ANIMATION_FLAG) == 0u && rand.x < 0.02) {
        if (get_texture_value(pos + vec3(0, 1, 0)).x == 0u && rand.z < 0.1) {
            textureStore(voxel_worlds, (pos + vec3(0, 1, 0)).zyx, vec4(44u | (material.y << 8u)));
        }

        // pick a random offset to check
        let i = i32(8.0 * rand.y);

        var offset: vec3<i32>;
        if (i == 0) {
            offset = vec3(1, 1, 0);
        } else if (i == 1) {
            offset = vec3(-1, 1, 0);
        } else if (i == 2) {
            offset = vec3(0, 1, 1);
        } else if (i == 3) {
            offset = vec3(0, 1, -1);
        } else if (i == 4) {
            offset = vec3(1, 0, 0);
        } else if (i == 5) {
            offset = vec3(-1, 0, 0);
        } else if (i == 6) {
            offset = vec3(0, 0, 1);
        } else if (i == 7) {
            offset = vec3(0, 0, -1);
        }

        let new_pos = pos + offset;
        let new_mat = get_texture_value(new_pos);

        if (in_texture_bounds(new_pos) && new_mat.x != 0u) {
            textureStore(voxel_worlds, new_pos.zyx, vec4(material.x | (material.y << 8u)));
        }
    }
    */

    // sand
    if (material.x != 0u && (material.y & SAND_FLAG) > 0u) {
        let new_pos = pos + vec3(0, -1, 0);
        let new_chunk_index = get_chunk_index(vec3<f32>(new_pos));
        if (new_chunk_index != -1) {
            let new_mat = get_texture_value(new_pos % vec3(i32(voxel_uniforms.chunk_size)), new_chunk_index);

            if (in_texture_bounds(new_pos) && new_mat.x == 0u) {
                textureStore(voxel_worlds[new_chunk_index], new_pos.zyx, vec4(material.x | (material.y << 8u)));
                textureStore(voxel_worlds[new_chunk_index], pos.zyx, vec4(0u));
            } else {
                let rand = hash(pos_time_seed);
                for (var i = 0; i < 4; i += 1) {
                    // start in a random direction
                    i = (i + i32(4.0 * rand.x)) % 4;

                    var offset: vec3<i32>;
                    if (i == 0) {
                        offset = vec3(1, -1, 0);
                    } else if (i == 1) {
                        offset = vec3(-1, -1, 0);
                    } else if (i == 2) {
                        offset = vec3(0, -1, 1);
                    } else if (i == 3) {
                        offset = vec3(0, -1, -1);
                    }

                    let new_pos = pos + offset;
                    let new_mat = get_texture_value(new_pos, new_chunk_index);

                    if (in_texture_bounds(new_pos) && new_mat.x == 0u) {
                        textureStore(voxel_worlds[new_chunk_index], new_pos.zyx, vec4(material.x | (material.y << 8u)));
                        textureStore(voxel_worlds[new_chunk_index], pos.zyx, vec4(0u));
                        break;
                    }
                }
            }
        }
    }

    // fire
    if (material.x >= 9u && material.x <= 13u) {
        let rand = hash(pos_time_seed + 1u);
        let i = i32(5.0 * rand.x);

        var offset: vec3<i32>;
        if (i == 0) {
            offset = vec3(1, 1, 0);
        } else if (i == 1) {
            offset = vec3(-1, 1, 0);
        } else if (i == 2) {
            offset = vec3(0, 1, 1);
        } else if (i == 3) {
            offset = vec3(0, 1, -1);
        } else if (i == 4) {
            offset = vec3(0, 1, 0);
        }

        let new_pos = pos + offset;
        let new_mat = get_texture_value(new_pos,  chunk_index);
        if (in_texture_bounds(new_pos) && new_mat.x == 0u && rand.z > 0.08) {
            let new_material = min(material.x + u32(rand.y * 1.3), 13u);
            textureStore(voxel_worlds[chunk_index], new_pos.zyx, vec4(new_material | (AUTOMATA_FLAG << 8u)));
        }

        if (rand.y < (f32(material.x) + 7.0) / 20.0 && (material.y & AUTOMATA_FLAG) > 0u) {
            textureStore(voxel_worlds[chunk_index], pos.zyx, vec4(0u));
        }
    }

    /*
    // fire spreading
    let fire_rand = hash(pos_time_seed + 30u);

    if material.x >= 9u && material.x <= 10u {
        // pick a random offset to check
        let i = i32(6.0 * fire_rand.y);

        var offset: vec3<i32>;
        if (i == 0) {
            offset = vec3(1, 0, 0);
        } else if (i == 1) {
            offset = vec3(-1, 0, 0);
        } else if (i == 2) {
            offset = vec3(0, 1, 0);
        } else if (i == 3) {
            offset = vec3(0, -1, 0);
        } else if (i == 4) {
            offset = vec3(0, 0, 1);
        } else if (i == 5) {
            offset = vec3(0, 0, -1);
        }

        let new_pos = pos + offset;
        let new_mat = get_texture_value(new_pos);

        if in_texture_bounds(new_pos) && new_mat.x == 8u {
            textureStore(voxel_worlds, pos.zyx, vec4(0u));
        } else if in_texture_bounds(new_pos) 
            && new_mat.x != 0u 
            && (new_mat.y & COLLISION_FLAG) > 0u
            && fire_rand.x < 0.1
        {
            textureStore(voxel_worlds, new_pos.zyx, vec4(material.x | (COLLISION_FLAG << 8u)));
        }
    }
    */

    // water
    if (material.x == 8u && (material.y & ANIMATION_FLAG) == 0u) {
        let new_pos = pos + vec3(0, -1, 0);
        let new_mat = get_texture_value(new_pos, chunk_index);

        if (in_texture_bounds(new_pos) && new_mat.x == 0u) {
            textureStore(voxel_worlds[chunk_index], new_pos.zyx, vec4(material.x | (material.y << 8u)));
            textureStore(voxel_worlds[chunk_index], pos.zyx, vec4(0u));
        } else {
            let rand = hash(pos_time_seed);
            for (var i = 0; i < 4; i += 1) {
                // start in a random direction
                i = (i + i32(4.0 * rand.x)) % 4;

                var offset: vec3<i32>;
                if (i == 0) {
                    offset = vec3(1, 0, 0);
                } else if (i == 1) {
                    offset = vec3(-1, 0, 0);
                } else if (i == 2) {
                    offset = vec3(0, 0, 1);
                } else if (i == 3) {
                    offset = vec3(0, 0, -1);
                }

                var safe = true;
                for (var j = 0; j < 4; j++) {
                    var check: vec3<i32>;
                    if (j == 0) {
                        check = vec3(1, 0, 0);
                    } else if (j == 1) {
                        check = vec3(-1, 0, 0);
                    } else if (j == 2) {
                        check = vec3(0, 0, 1);
                    } else if (j == 3) {
                        check = vec3(0, 0, -1);
                    }

                    if (any(offset != -check)) {
                        let check_pos = pos + offset + check;
                        let check_mat = get_texture_value(new_pos,  chunk_index);

                        if (in_texture_bounds(check_pos) && check_mat.x == 8u) {
                            safe = false;
                            break;
                        }
                    }
                }

                if (safe) {
                    let new_pos = pos + offset;
                    let new_mat = get_texture_value(new_pos,  chunk_index);

                    if (in_texture_bounds(new_pos) && new_mat.x == 0u) {
                        textureStore(voxel_worlds[chunk_index], new_pos.zyx, vec4(material.x | (material.y << 8u)));
                        textureStore(voxel_worlds[chunk_index], pos.zyx, vec4(0u));
                    }

                    break;
                }
            }
        }
    }
}