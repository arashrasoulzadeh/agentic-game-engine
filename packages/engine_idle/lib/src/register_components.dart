import 'package:engine_core/engine_core.dart';

/// Registers the idle-genre components on [world] so they take part in `World.toJson()`,
/// `applyPatch()` and level loading like any other component. Call it after
/// `registerCoreComponents`.
///
/// Nothing is registered yet: components arrive with the generator / upgrade / prestige work in
/// `TODO_IDLE.md`, and each must be added here with a schema (an unregistered component silently
/// cannot be serialized).
void registerIdleComponents(World world) {}
