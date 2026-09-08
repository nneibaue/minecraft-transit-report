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

import java.util.List;

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
