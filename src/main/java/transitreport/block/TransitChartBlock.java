package transitreport.block;

import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.EntityBlock;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

import java.util.List;
import java.util.Map;

import transitreport.JollyalchemyTransitReport;
import transitreport.block.entity.TransitChartBlockEntity;

/**
 * A block that stores a 4-way horizontal facing state, derived from the direction the
 * placing player was looking so the block's front face looks back at them (BLOCK-03, D-04).
 *
 * <p>Intentionally extends {@link HorizontalDirectionalBlock} rather than
 * {@link net.minecraft.world.level.block.BaseEntityBlock}: adding {@link EntityBlock} directly
 * to this base class (04-01-PLAN.md Task 1, per 02-CONTEXT.md D-08's landmine) keeps the
 * inherited {@code FACING}/{@code rotate}/{@code mirror} plumbing and avoids the render-shape
 * override that {@code BaseEntityBlock} defaults to {@code RenderShape.INVISIBLE}, which would
 * make the block invisible if that base class were picked up here instead.
 */
public class TransitChartBlock extends HorizontalDirectionalBlock implements EntityBlock {
	// Thin wall-mounted outline/collision shape, keyed by FACING (04-01 checkpoint feedback,
	// post visual review in-game: the default full-cube shape made the block visibly protrude
	// a whole block's depth out from the wall). Confirmed vanilla precedent via javap against
	// this project's own compiled jar: WallBannerBlock builds an identical Map<Direction,
	// VoxelShape> using Block.box(x1,y1,z1,x2,y2,z2) (Mojmap -- on Block, not Shapes), keyed by
	// FACING, with the thin slab positioned at the face OPPOSITE FACING (the wall/mounting
	// surface side). Same convention applies here: the chart quad renders on the FACING side
	// (TransitChartRenderer), so the thin slab hugs the opposite face, flush against whatever
	// surface the block is mounted against. 2 of 16 units (0.125 blocks) deep.
	private static final Map<Direction, VoxelShape> SHAPES = Map.of(
			Direction.NORTH, Block.box(0.0, 0.0, 14.0, 16.0, 16.0, 16.0),
			Direction.SOUTH, Block.box(0.0, 0.0, 0.0, 16.0, 16.0, 2.0),
			Direction.WEST, Block.box(14.0, 0.0, 0.0, 16.0, 16.0, 16.0),
			Direction.EAST, Block.box(0.0, 0.0, 0.0, 2.0, 16.0, 16.0));

	public TransitChartBlock(BlockBehaviour.Properties properties) {
		super(properties);
		this.registerDefaultState(this.stateDefinition.any().setValue(FACING, Direction.NORTH));
	}

	@Override
	protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
		builder.add(FACING);
	}

	@Override
	public BlockState getStateForPlacement(BlockPlaceContext context) {
		return this.defaultBlockState().setValue(FACING, context.getHorizontalDirection().getOpposite());
	}

	// Outline shape only -- BlockBehaviour's default getCollisionShape() already delegates to
	// this method whenever the block has collision (true by default here, unmodified), confirmed
	// via javap against BlockBehaviour's compiled bytecode. A separate getCollisionShape()
	// override would just duplicate the same box() coordinates in two places and risk them
	// silently drifting apart later -- WallBannerBlock (the vanilla precedent this follows)
	// overrides only getShape() for the same reason.
	@Override
	public VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
		return SHAPES.get(state.getValue(FACING));
	}

	@Override
	public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
		return new TransitChartBlockEntity(pos, state);
	}

	// Tooltip lines for the item (BLOCK-06, GEN-05). BlockItem.appendHoverText already
	// delegates to this block-level method - no BlockItem subclass is needed (confirmed via
	// bytecode disassembly, 03-RESEARCH.md Pattern 3). Note the second parameter is
	// BlockGetter here, not Level - that is the item-level appendHoverText signature and
	// writing it here would silently never be called.
	@Override
	public void appendHoverText(ItemStack stack, BlockGetter level, List<Component> tooltip, TooltipFlag flag) {
		tooltip.add(Component.translatable("item." + JollyalchemyTransitReport.MOD_ID + ".transit_chart.tooltip"));
		tooltip.add(Component.translatable("item." + JollyalchemyTransitReport.MOD_ID + ".transit_chart.flavor")
				.withStyle(ChatFormatting.ITALIC));
	}
}
