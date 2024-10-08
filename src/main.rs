use bevy::{
    core_pipeline::{
        bloom::{BloomPrefilterSettings, BloomSettings},
        fxaa::Fxaa,
    },
    prelude::*,
    render::{
        settings::{RenderCreation, WgpuSettings},
        RenderPlugin,
    },
};
use bevy_obj::*;
use bevy_voxel_engine::*;
use character::CharacterEntity;
use rand::Rng;
use std::f32::consts::PI;
use wgpu::Backends;

#[path = "common/character.rs"]
mod character;

#[path = "common/fps_counter.rs"]
mod fps_counter;

#[path = "common/ui.rs"]
mod ui;

// zero: normal bullet
// one: orange portal bullet
// two: blue portal bullet
#[derive(Component)]
pub struct Bullet {
    bullet_type: u32,
}

#[derive(Component)]
struct CharacterPortals {
    portal1: Entity,
    portal2: Entity,
}

fn main() {
    let mut app = App::new();

    app.add_plugins((
        DefaultPlugins.set(RenderPlugin {
            render_creation: RenderCreation::Automatic(WgpuSettings {
                backends: Some(
                    Backends::BROWSER_WEBGPU | Backends::GL | Backends::VULKAN | Backends::METAL,
                ),
                ..default()
            }),
            ..default()
        }),
        ObjPlugin,
        BevyVoxelEnginePlugin,
        character::Character,
        ui::UiPlugin,
        fps_counter::FpsCounter,
    ))
    .add_systems(Startup, setup)
    .add_systems(
        Update,
        (
            //update_suzanne,
            shoot,
            update_fire,
            spawn_stuff,
        ),
    );

    app.run();
}

// world space cordinates are in terms of 4 voxels per meter with 0, 0
// in the world lining up with the center of the voxel world and the edge
// of the world being half of the world size in each direction
fn setup(
    mut commands: Commands,
    mut load_voxel_world: ResMut<LoadVoxelWorld>,
    asset_server: Res<AssetServer>,
) {
    // load a voxel world
    *load_voxel_world = LoadVoxelWorld::File("assets/monu9.vox".to_string());

    // character portals
    let mut character_portals = vec![None; 2];

    for i in 0..2 {
        character_portals[i] = Some(
            commands
                .spawn((
                    VoxelizationBundle {
                        mesh_handle: asset_server.load("models/portal.obj"),
                        transform: Transform::from_xyz(0.0, 100.0, 0.0)
                            .looking_at(Vec3::ZERO, Vec3::Y)
                            .with_scale(Vec3::new(i as f32 * 2.0 - 1.0, 1.0, i as f32 * 2.0 - 1.0)),
                        voxelization_material: VoxelizationMaterial {
                            flags: Flags::ANIMATION_FLAG | Flags::PORTAL_FLAG,
                            ..default()
                        },
                        ..default()
                    },
                    Portal,
                ))
                .with_children(|parent| {
                    // portal border
                    parent.spawn(VoxelizationBundle {
                        mesh_handle: asset_server.load("models/portal_frame.obj"),
                        voxelization_material: VoxelizationMaterial {
                            material: VoxelizationMaterialType::Material(120 + i as u8),
                            flags: Flags::ANIMATION_FLAG | Flags::COLLISION_FLAG,
                        },
                        ..default()
                    });
                })
                .id(),
        );
    }

    // Character
    let character_transform = Transform::from_xyz(0.0, 60.0, 0.0).looking_at(Vec3::ZERO, Vec3::Y);

    let projection = Projection::Perspective(PerspectiveProjection {
        fov: PI / 4.0,
        ..default()
    });

    commands
        .spawn((
            VoxelCameraBundle {
                transform: character_transform,
                projection: projection.clone(),
                ..default()
            },
            CharacterEntity {
                in_spectator: false,
                grounded: false,
                look_at: -*character_transform.local_z(),
                up: Vec3::new(0.0, 1.0, 0.0),
            },
            CharacterPortals {
                portal1: character_portals[0].unwrap(),
                portal2: character_portals[1].unwrap(),
            },
            VoxelPhysics::new(
                Vec3::splat(0.0),
                Vec3::ZERO, // Gravity handeled in character.rs
                CollisionEffect::None,
            ),
            BoxCollider {
                half_size: IVec3::new(2, 4, 2),
            },
            BloomSettings::default(),
            Fxaa::default(),
        ))
        .with_children(|parent| {
            // voxelization preview camera
            parent.spawn((
                Camera3dBundle {
                    camera: Camera {
                        is_active: false,
                        order: 10, // render after the main camera
                        ..default()
                    },
                    projection,
                    ..default()
                },
                BloomSettings::default(),
                Fxaa::default(),
                VoxelizationPreviewCamera,
            ));
        });

    // Rotated portals

    let pos = vec![Vec3::new(5.0, 0.0, -5.0), Vec3::new(-5.0, 0.0, 5.0)];

    for i in 0..2 {
        commands
            .spawn((
                VoxelizationBundle {
                    mesh_handle: asset_server.load("models/portal.obj"),
                    transform: Transform::from_translation(pos[i])
                        .looking_at(Vec3::ZERO, Vec3::Y)
                        .with_scale(Vec3::new(i as f32 * 2.0 - 1.0, 1.0, i as f32 * 2.0 - 1.0)),
                    voxelization_material: VoxelizationMaterial {
                        flags: Flags::ANIMATION_FLAG | Flags::PORTAL_FLAG,
                        ..default()
                    },
                    ..default()
                },
                Portal,
            ))
            .with_children(|parent| {
                // Portal border
                parent.spawn(VoxelizationBundle {
                    mesh_handle: asset_server.load("models/portal_frame.obj"),
                    voxelization_material: VoxelizationMaterial {
                        material: VoxelizationMaterialType::Material(120 + i as u8),
                        flags: Flags::ANIMATION_FLAG | Flags::COLLISION_FLAG,
                    },
                    ..default()
                });
            });
    }

    /*
    // voxelized mesh
    commands.spawn((
        VoxelizationBundle {
            mesh_handle: asset_server.load("models/suzanne.obj"),
            voxelization_material: VoxelizationMaterial {
                material: VoxelizationMaterialType::Texture(
                    asset_server.load("models/suzanne.png"),
                ),
                flags: Flags::COLLISION_FLAG | Flags::ANIMATION_FLAG,
            },
            transform: Transform::from_scale(Vec3::splat(3.0)).looking_at(Vec3::Z, Vec3::Y),
            ..default()
        },
        Suzanne,
    ));
    */
}

#[derive(Component)]
struct VoxelizationPreviewCamera;
#[derive(Component)]
struct Suzanne;

fn update_suzanne(time: Res<Time>, mut cube: Query<&mut Transform, With<Suzanne>>) {
    for mut transform in cube.iter_mut() {
        transform.rotate_x(1.5 * time.delta_seconds());
        transform.rotate_z(1.3 * time.delta_seconds());
    }
}

fn shoot(
    mut commands: Commands,
    keyboard: Res<ButtonInput<KeyCode>>,
    mut character: Query<(&Transform, &mut CharacterEntity)>,
) {
    let (transform, mut character_entity) = character.single_mut();

    if keyboard.just_pressed(KeyCode::Digit1) {
        commands.spawn((
            Transform::from_translation(transform.translation),
            Particle {
                material: 120,
                flags: Flags::ANIMATION_FLAG,
            },
            VoxelPhysics::new(
                -transform.local_z() * 50.0,
                Vec3::new(0.0, -9.81, 0.0),
                CollisionEffect::None,
            ),
            Bullet { bullet_type: 1 },
        ));
    }
    if keyboard.just_pressed(KeyCode::Digit2) {
        commands.spawn((
            Transform::from_translation(transform.translation),
            Particle {
                material: 121,
                flags: Flags::ANIMATION_FLAG,
            },
            VoxelPhysics::new(
                -transform.local_z() * 50.0,
                Vec3::new(0.0, -9.81, 0.0),
                CollisionEffect::None,
            ),
            Bullet { bullet_type: 2 },
        ));
    }

    if keyboard.just_pressed(KeyCode::KeyE) {
        println!("Pressed E");

        commands.spawn((
            Transform::from_translation(transform.translation),
            Particle {
                material: 120,
                flags: Flags::ANIMATION_FLAG,
            },
            VoxelPhysics::new(
                -transform.local_z() * 50.0,
                Vec3::new(0.0, -9.81, 0.0),
                CollisionEffect::SetFlags {
                    radius: 3.0,
                    flags: Flags::SAND_FLAG,
                },
            ),
            Bullet { bullet_type: 0 },
        ));
    }

    if keyboard.just_pressed(KeyCode::KeyP) {
        character_entity.in_spectator = !character_entity.in_spectator;
    }

    if keyboard.just_pressed(KeyCode::KeyB) {
        commands.spawn((
            Transform::from_translation(transform.translation),
            VoxelPhysics::new(
                -transform.local_z() * 10.0,
                Vec3::new(0.0, -9.81, 0.0),
                CollisionEffect::None,
            ),
            Bullet { bullet_type: 0 },
            BoxCollider {
                half_size: IVec3::new(3, 3, 3),
            },
            Box {
                material: 14,
                flags: Flags::ANIMATION_FLAG,
                half_size: IVec3::new(3, 3, 3),
            },
        ));
    }
}

fn update_fire(mut particle_query: Query<(Entity, &mut Particle)>, mut commands: Commands) {
    let mut rand = rand::thread_rng();
    for (entity, mut particle) in particle_query.iter_mut() {
        if particle.material >= 9 && particle.material <= 13 {
            particle.material += rand.gen_range(0.0..1.02) as u8;
            if particle.material == 11 {
                commands.entity(entity).despawn();
            }
        }
    }
}

fn spawn_stuff(
    mut commands: Commands,
    bullet_query: Query<(&Transform, &VoxelPhysics, &Bullet, Entity)>,
    character_query: Query<&CharacterPortals>,
    mut portal_query: Query<&mut Transform, (With<Portal>, Without<Bullet>)>,
) {
    for (transform, velocity, bullet, entity) in bullet_query.iter() {
        if velocity.hit_normal != Vec3::splat(0.0) {
            commands.entity(entity).despawn();

            if bullet.bullet_type == 1 || bullet.bullet_type == 2 {
                let normal = velocity.hit_normal;

                let plane = 1.0 - normal.abs();
                let pos =
                    (transform.translation * plane * VOXELS_PER_METER).floor() / VOXELS_PER_METER;
                let pos = pos + transform.translation * normal.abs();

                let character_portals = character_query.single();
                let entity = match bullet.bullet_type {
                    1 => character_portals.portal1,
                    2 => character_portals.portal2,
                    _ => panic!(),
                };

                let up = if normal.abs() == Vec3::Y {
                    Vec3::Z
                } else {
                    Vec3::Y
                };

                let mut transform = portal_query.get_mut(entity).unwrap();
                transform.translation = pos;
                transform.look_at(pos + normal, up);
            }

            if bullet.bullet_type == 0 {
                println!("hit");

                let mut rng = rand::thread_rng();
                for _ in 0..100 {
                    commands.spawn((
                        Transform::from_translation(transform.translation),
                        Particle {
                            material: 9,
                            flags: Flags::AUTOMATA_FLAG,
                        },
                        VoxelPhysics::new(
                            Vec3::new(
                                rng.gen_range(-1.0..1.0),
                                rng.gen_range(-1.0..1.0),
                                rng.gen_range(-1.0..1.0),
                            ) * 10.0,
                            Vec3::new(0.0, -9.81, 0.0),
                            bevy_voxel_engine::CollisionEffect::None,
                        ),
                    ));
                }
            }
        }
    }
}
