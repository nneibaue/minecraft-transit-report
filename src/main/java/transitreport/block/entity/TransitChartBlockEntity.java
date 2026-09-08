package transitreport.block.entity;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;

import transitreport.TransitReportBlocks;

/**
 * Block entity for {@link transitreport.block.TransitChartBlock}. This phase (04-01) it exists
 * purely as plumbing for {@code TransitChartRenderer} to attach to -- no persisted state, no NBT.
 *
 * <p>Deliberately has no {@code getRenderBoundingBox()} override: that method does not exist on
 * this Minecraft version (04-01-PLAN.md Correction 1, confirmed via javap against this project's
 * own compiled jars). The real mechanism for "this block entity's render extends past its own
 * footprint and must not be culled" is {@code BlockEntityRenderer.shouldRenderOffScreen(T)},
 * overridden on {@code TransitChartRenderer} instead.
 */
public class TransitChartBlockEntity extends BlockEntity {
	public TransitChartBlockEntity(BlockPos pos, BlockState state) {
		super(TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY, pos, state);
	}
}
