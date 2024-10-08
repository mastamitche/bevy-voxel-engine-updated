#define_import_path bevy_voxel_engine::raytracing

#import bevy_voxel_engine::common::{
    VOXELS_PER_METER,
    PORTAL_FLAG,
    VoxelUniforms,
    Ray,
    ray_plane,
    in_bounds,
    ray_box_dist,
}
#import bevy_voxel_engine::bindings::{
    voxel_worlds,
    voxel_uniforms,
    gh
}

fn get_value_index(index: u32) -> bool {
    return ((gh[index / 32u] >> (index % 32u)) & 1u) != 0u;
}

struct Voxel {
    data: u32,
    pos: vec3<f32>,
    grid_size: u32,
};
fn get_value(pos: vec3<f32>, chunk_index: i32) -> Voxel {
    let scaled = pos * 0.5 + 0.5;

    let size0 = voxel_uniforms.levels[0].x;
    let size1 = voxel_uniforms.levels[1].x;
    let size2 = voxel_uniforms.levels[2].x;
    let size3 = voxel_uniforms.levels[3].x;
    let size4 = voxel_uniforms.levels[4].x;
    let size5 = voxel_uniforms.levels[5].x;
    let size6 = voxel_uniforms.levels[6].x;
    let size7 = voxel_uniforms.levels[7].x;

    let scaled0 = vec3<u32>(scaled * f32(size0));
    let scaled1 = vec3<u32>(scaled * f32(size1));
    let scaled2 = vec3<u32>(scaled * f32(size2));
    let scaled3 = vec3<u32>(scaled * f32(size3));
    let scaled4 = vec3<u32>(scaled * f32(size4));
    let scaled5 = vec3<u32>(scaled * f32(size5));
    let scaled6 = vec3<u32>(scaled * f32(size6));
    let scaled7 = vec3<u32>(scaled * f32(size7));

    let state0 = get_value_index(voxel_uniforms.offsets[0].x + scaled0.x * size0 * size0 + scaled0.y * size0 + scaled0.z);
    let state1 = get_value_index(voxel_uniforms.offsets[1].x + scaled1.x * size1 * size1 + scaled1.y * size1 + scaled1.z);
    let state2 = get_value_index(voxel_uniforms.offsets[2].x + scaled2.x * size2 * size2 + scaled2.y * size2 + scaled2.z);
    let state3 = get_value_index(voxel_uniforms.offsets[3].x + scaled3.x * size3 * size3 + scaled3.y * size3 + scaled3.z);
    let state4 = get_value_index(voxel_uniforms.offsets[4].x + scaled4.x * size4 * size4 + scaled4.y * size4 + scaled4.z);
    let state5 = get_value_index(voxel_uniforms.offsets[5].x + scaled5.x * size5 * size5 + scaled5.y * size5 + scaled5.z);
    let state6 = get_value_index(voxel_uniforms.offsets[6].x + scaled6.x * size6 * size6 + scaled6.y * size6 + scaled6.z);
    let state7 = get_value_index(voxel_uniforms.offsets[7].x + scaled7.x * size7 * size7 + scaled7.y * size7 + scaled7.z);

    if (!state0 && size0 != 0u) {
        let rounded_pos = ((vec3<f32>(scaled0) + 0.5) / f32(size0)) * 2.0 - 1.0;
        return Voxel(0u, rounded_pos, size0);
    }
    if (!state1 && size1 != 0u) {
        let rounded_pos = ((vec3<f32>(scaled1) + 0.5) / f32(size1)) * 2.0 - 1.0;
        return Voxel(0u, rounded_pos, size1);
    }
    if (!state2 && size2 != 0u) {
        let rounded_pos = ((vec3<f32>(scaled2) + 0.5) / f32(size2)) * 2.0 - 1.0;
        return Voxel(0u, rounded_pos, size2);
    }
    if (!state3 && size3 != 0u) {
        let rounded_pos = ((vec3<f32>(scaled3) + 0.5) / f32(size3)) * 2.0 - 1.0;
        return Voxel(0u, rounded_pos, size3);
    }
    if (!state4 && size4 != 0u) {
        let rounded_pos = ((vec3<f32>(scaled4) + 0.5) / f32(size4)) * 2.0 - 1.0;
        return Voxel(0u, rounded_pos, size4);
    }
    if (!state5 && size5 != 0u) {
        let rounded_pos = ((vec3<f32>(scaled5) + 0.5) / f32(size5)) * 2.0 - 1.0;
        return Voxel(0u, rounded_pos, size5);
    }
    if (!state6 && size6 != 0u) {
        let rounded_pos = ((vec3<f32>(scaled6) + 0.5) / f32(size6)) * 2.0 - 1.0;
        return Voxel(0u, rounded_pos, size6);
    }
    if (!state7 && size7 != 0u) {
        let rounded_pos = ((vec3<f32>(scaled7) + 0.5) / f32(size7)) * 2.0 - 1.0;
        return Voxel(0u, rounded_pos, size7);
    }
    let rounded_pos = (floor(pos * f32(voxel_uniforms.texture_size) * 0.5) + 0.5) / (f32(voxel_uniforms.texture_size) * 0.5);
    let data = textureLoad(voxel_worlds[chunk_index], vec3<i32>(scaled * f32(voxel_uniforms.texture_size)).zyx).r;

    return Voxel(data, rounded_pos, voxel_uniforms.texture_size);
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
struct HitInfo {
    hit: bool,
    data: u32,
    material: vec4<f32>,
    pos: vec3<f32>,
    reprojection_pos: vec3<f32>,
    normal: vec3<f32>,
    portals: mat4x4<f32>,
    steps: u32,
};

const IDENTITY = mat4x4<f32>(
    vec4<f32>(1.0, 0.0, 0.0, 0.0), 
    vec4<f32>(0.0, 1.0, 0.0, 0.0), 
    vec4<f32>(0.0, 0.0, 1.0, 0.0),
    vec4<f32>(0.0, 0.0, 0.0, 1.0),
);

fn intersect_scene(r: Ray, steps: u32) -> HitInfo {
    let rtw = f32(voxel_uniforms.texture_size) / (VOXELS_PER_METER * 2.0); // render to world ratio

    let normal = vec3(0.0, 1.0, 0.0);
    let hit = ray_plane(r, vec3(0.0, -1.0, 0.0), normal).xyz;

    if (any(hit != vec3(0.0))) {
        let pos = hit + normal * 0.000002;

        // green floor
        let color = vec3(113.0, 129.0, 44.0) / 255.0;

        return HitInfo(true, 0u, vec4(color, 0.0), pos * rtw, pos * rtw, normal, IDENTITY, steps);
    }

    let infinity = 1000000000.0 * r.dir;

    return HitInfo(false, 0u, vec4(0.0), infinity, infinity, vec3(0.0), IDENTITY, steps);
}

/// physics_distance is in terms of t so make sure to normalize your 
/// ray direction if you want it to be in world cordinates.
/// only hits voxels that have any of the flags set or hits everything if flags is 0
fn shoot_ray(r: Ray, physics_distance: f32, flags: u32) -> HitInfo {
    let wtr = VOXELS_PER_METER * 2.0 / f32(voxel_uniforms.texture_size); // world to render
    let rtw = f32(voxel_uniforms.texture_size) / (VOXELS_PER_METER * 2.0); // render to world

    var pos = r.pos * wtr;
    let dir_mask = vec3<f32>(r.dir == vec3(0.0));
    var dir = r.dir + dir_mask * 0.000001;

    var distance = 0.0;
    if (!in_bounds(pos)) {
        // Get position on surface of the octree
        let dist = ray_box_dist(Ray(pos, dir), vec3(-1.0), vec3(1.0)).x;

        if (dist == 0.0) {
            if (physics_distance * wtr > 0.0) {
                return HitInfo(false, 0u, vec4(0.0), (pos + dir * physics_distance * wtr) * rtw, vec3(0.0), vec3(0.0), IDENTITY, 1u);
            }
            return intersect_scene(Ray(pos, dir), 1u);
        }

        pos = pos + dir * dist;
        distance += dist;
    }

    var r_sign = sign(dir);
    var tcpotr = pos; // the current position of the ray
    var steps = 0u;
    var normal = trunc(pos * 1.00001);
    var voxel = Voxel(0u, vec3(0.0), 0u);
    var portal_mat = IDENTITY;
    var reprojection_pos = pos;
    while (steps < 100u) {
        let chunk_index = get_chunk_index(tcpotr);
        if (chunk_index == -1) {
            break; // Ray has left the active chunks
        }

        voxel = get_value(tcpotr, chunk_index);

        let should_portal_skip = ((voxel.data >> 8u) & PORTAL_FLAG) > 0u;
        if ((voxel.data & 0xFFu) != 0u && !should_portal_skip && (((voxel.data >> 8u) & flags) > 0u || flags == 0u)) {
            break;
        }

        let voxel_size = 2.0 / f32(voxel.grid_size);
        let t_max = (voxel.pos - pos + r_sign * voxel_size / 2.0) / dir;

        // https://www.shadertoy.com/view/4dX3zl (good old shader toy)
        let mask = vec3<f32>(t_max.xyz <= min(t_max.yzx, t_max.zxy));
        normal = mask * -r_sign;

        let t_current = min(min(t_max.x, t_max.y), t_max.z);
        tcpotr = pos + dir * t_current - normal * 0.000002;
        reprojection_pos = r.pos + (t_current + distance) * r.dir * rtw;

        // portals
        if (should_portal_skip) {
            let portal = voxel_uniforms.portals[i32(voxel.data & 0xFFu)];

            let intersection = ray_plane(Ray(pos * rtw, dir), portal.position + portal.normal * 0.00002, portal.normal);
            if (intersection.w != 0.0 && intersection.w * wtr < t_current) {
                pos = (portal.transformation * vec4(intersection.xyz - portal.normal * 0.00004, 1.0)).xyz * wtr;
                dir = (portal.transformation * vec4(dir, 0.0)).xyz;
                r_sign = sign(dir);
                tcpotr = pos;

                portal_mat = portal.transformation * portal_mat;

                //return HitInfo(true, voxel.data, vec4(tcpotr, 0.0), tcpotr * rtw + normal * 0.0001, reprojection_pos, normal, portal_mat, steps);
            }
        }

        if (t_current + distance > physics_distance * wtr && physics_distance > 0.0) {
            return HitInfo(false, 0u, vec4(0.0), (pos + dir * (physics_distance * wtr - distance)) * rtw, vec3(0.0), vec3(0.0), portal_mat, steps);
        }

        if (!in_bounds(tcpotr)) {
            if (physics_distance > 0.0) {
                return HitInfo(false, 0u, vec4(0.0), (pos + dir * (physics_distance * wtr - distance)) * rtw, vec3(0.0), vec3(0.0), portal_mat, steps);
            }

            return intersect_scene(Ray(pos, dir), steps);
        }

        steps = steps + 1u;
    }

    return HitInfo(true, voxel.data, voxel_uniforms.materials[voxel.data & 0xFFu], tcpotr * rtw + normal * 0.0001, reprojection_pos, normal, portal_mat, steps);
}