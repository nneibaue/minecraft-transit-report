package transitreport;

import net.fabricmc.fabric.api.itemgroup.v1.ItemGroupEvents;

import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.CreativeModeTabs;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.minecraft.world.level.block.state.BlockBehaviour;

import transitreport.block.TransitChartBlock;
import transitreport.block.entity.TransitChartBlockEntity;

/**
 * Registration holder for this mod's blocks and their block items (D-09). Holds the block
 * and item as {@code public static final} fields so the datagen model provider in
 * {@code src/client} can reference the same instances registered here in {@code src/main},
 * and exposes an explicit {@link #register()} entry point: Java does not run a class's
 * static field initializers until the class is first touched, so relying on static
 * initialization alone would leave these registrations silently never run.
 */
public final class TransitReportBlocks {
	public static final Block TRANSIT_CHART = new TransitChartBlock(
			BlockBehaviour.Properties.of()
					.strength(1.5F)
					.sound(SoundType.AMETHYST)
					// 04-01 checkpoint feedback, round 3: this was a normal full opaque cube
					// through Phase 2/3, correct at the time. TransitChartBlock is now a thin,
					// invisible, non-full block (getRenderShape() = INVISIBLE, getShape() = a
					// thin slab) -- without noOcclusion(), vanilla's neighbor face-culling still
					// treats it as occluding, leaving a rendering hole in the wall block behind
					// it until an unrelated chunk rebuild (e.g. breaking the block) recalculates
					// it. noOcclusion() confirmed via javap against this project's compiled
					// BlockBehaviour$Properties.class.
					.noOcclusion());

	public static final Item TRANSIT_CHART_ITEM = new BlockItem(TRANSIT_CHART, new Item.Properties());

	// Passing null as the validation-context data fixer type is the standard vanilla pattern
	// for a block entity with no NBT to migrate (04-01-PLAN.md Task 1).
	public static final BlockEntityType<TransitChartBlockEntity> TRANSIT_CHART_BLOCK_ENTITY =
			BlockEntityType.Builder.of(TransitChartBlockEntity::new, TRANSIT_CHART).build(null);

	private TransitReportBlocks() {
	}

	public static void register() {
		Registry.register(BuiltInRegistries.BLOCK, JollyalchemyTransitReport.id("transit_chart"), TRANSIT_CHART);
		Registry.register(BuiltInRegistries.ITEM, JollyalchemyTransitReport.id("transit_chart"), TRANSIT_CHART_ITEM);
		Registry.register(BuiltInRegistries.BLOCK_ENTITY_TYPE, JollyalchemyTransitReport.id("transit_chart"),
				TRANSIT_CHART_BLOCK_ENTITY);

		ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.FUNCTIONAL_BLOCKS)
				.register(entries -> entries.accept(TRANSIT_CHART_ITEM));
	}
}
