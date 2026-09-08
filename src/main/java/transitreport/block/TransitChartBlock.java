package transitreport.block;

import net.minecraft.core.Direction;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;

/**
 * A block that stores a 4-way horizontal facing state, derived from the direction the
 * placing player was looking so the block's front face looks back at them (BLOCK-03, D-04).
 *
 * <p>Intentionally extends {@link HorizontalDirectionalBlock} rather than
 * {@link net.minecraft.world.level.block.BaseEntityBlock}: no {@code BlockEntity} or
 * {@code BlockEntityType} is introduced this phase (D-08). {@code rotate} and {@code mirror}
 * are inherited unchanged from {@code HorizontalDirectionalBlock}.
 */
public class TransitChartBlock extends HorizontalDirectionalBlock {
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
}
