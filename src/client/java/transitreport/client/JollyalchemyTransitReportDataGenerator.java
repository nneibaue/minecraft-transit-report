package transitreport.client;

import net.fabricmc.fabric.api.datagen.v1.DataGeneratorEntrypoint;
import net.fabricmc.fabric.api.datagen.v1.FabricDataGenerator;
import net.fabricmc.fabric.api.datagen.v1.FabricDataOutput;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricBlockLootTableProvider;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricLanguageProvider;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricModelProvider;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricRecipeProvider;

import net.minecraft.data.models.BlockModelGenerators;
import net.minecraft.data.models.ItemModelGenerators;
import net.minecraft.data.models.model.TextureSlot;
import net.minecraft.data.models.model.TexturedModel;
import net.minecraft.data.recipes.FinishedRecipe;
import net.minecraft.data.recipes.RecipeCategory;
import net.minecraft.data.recipes.ShapelessRecipeBuilder;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.Items;

import java.util.function.Consumer;

import transitreport.JollyalchemyTransitReport;
import transitreport.TransitReportBlocks;

public class JollyalchemyTransitReportDataGenerator implements DataGeneratorEntrypoint {
	@Override
	public void onInitializeDataGenerator(FabricDataGenerator fabricDataGenerator) {
		FabricDataGenerator.Pack pack = fabricDataGenerator.createPack();
		pack.addProvider(TransitReportLanguageProvider::new);
		pack.addProvider(TransitChartModelProvider::new);
		pack.addProvider(TransitChartRecipeProvider::new);
		pack.addProvider(TransitChartLootTableProvider::new);
	}

	// Skeleton language provider: registers the one translation key this phase needs
	// (TOOL-02) with no block, item, or model required to exist. Phase 3's GEN-05 grows
	// this same class with the mod's real translation set rather than replacing it.
	private static final class TransitReportLanguageProvider extends FabricLanguageProvider {
		private TransitReportLanguageProvider(FabricDataOutput dataOutput) {
			super(dataOutput);
		}

		@Override
		public void generateTranslations(FabricLanguageProvider.TranslationBuilder translationBuilder) {
			translationBuilder.add("text." + JollyalchemyTransitReport.MOD_ID + ".refreshing", "Refreshing transit chart...");
			translationBuilder.add("block." + JollyalchemyTransitReport.MOD_ID + ".transit_chart", "Transit Chart");
		}
	}

	// Generates the blockstate and block model for TransitChartBlock (GEN-01). D-03 borrows
	// vanilla's furnace textures - no PNG is authored this phase. ORIENTABLE_ONLY_TOP (not
	// ORIENTABLE) is the 3-slot (front/side/top) provider matching vanilla's real furnace
	// model; createHorizontallyRotatedBlock (not createFurnace) is the pure FACING-only
	// dispatch matching TransitChartBlock's state definition, which has no LIT property.
	// See 02-RESEARCH.md Pitfalls 1 and 2.
	private static final class TransitChartModelProvider extends FabricModelProvider {
		private static final TexturedModel.Provider TRANSIT_CHART_TEXTURES = TexturedModel.ORIENTABLE_ONLY_TOP
				.updateTexture(mapping -> mapping
						.put(TextureSlot.FRONT, new ResourceLocation("minecraft", "block/furnace_front"))
						.put(TextureSlot.SIDE, new ResourceLocation("minecraft", "block/furnace_side"))
						.put(TextureSlot.TOP, new ResourceLocation("minecraft", "block/furnace_top")));

		private TransitChartModelProvider(FabricDataOutput output) {
			super(output);
		}

		@Override
		public void generateBlockStateModels(BlockModelGenerators blockModelGenerators) {
			blockModelGenerators.createHorizontallyRotatedBlock(TransitReportBlocks.TRANSIT_CHART, TRANSIT_CHART_TEXTURES);
		}

		@Override
		public void generateItemModels(ItemModelGenerators itemModelGenerators) {
			// Intentionally empty - Fabric's model provider auto-generates the block item's
			// model as a parent reference to the block model (RESEARCH.md Assumption A1).
		}
	}

	// Generates the active crafting recipe (BLOCK-04, GEN-03) plus the recipe-unlock
	// advancement Fabric emits alongside it. On 1.20.1, FabricRecipeProvider's single
	// abstract method is buildRecipes(Consumer<FinishedRecipe>) - not generateRecipes, and
	// neither builder below takes a CraftingBookCategory argument; both are post-1.21
	// signatures that do not exist here. See 03-RESEARCH.md Pattern 1.
	private static final class TransitChartRecipeProvider extends FabricRecipeProvider {
		private TransitChartRecipeProvider(FabricDataOutput output) {
			super(output);
		}

		@Override
		public void buildRecipes(Consumer<FinishedRecipe> exporter) {
			ShapelessRecipeBuilder.shapeless(RecipeCategory.MISC, TransitReportBlocks.TRANSIT_CHART_ITEM)
					.requires(Items.DIRT)
					.unlockedBy("has_dirt", has(Items.DIRT))
					.save(exporter, JollyalchemyTransitReport.id("transit_chart"));

			// Intended thematic recipe (GEN-06) - kept commented out beside the active one so
			// swapping it in is uncommenting, not rewriting. IMPORTANT: comment out or remove
			// the active ShapelessRecipeBuilder call above at the SAME TIME as uncommenting
			// this one - both target the same recipe id, and runDatagen throws
			// IllegalStateException("Duplicate recipe ...") the moment both are live at once.
			// Uncommenting this block also requires adding the currently-unused import
			// net.minecraft.data.recipes.ShapedRecipeBuilder.
			//
			// ShapedRecipeBuilder.shaped(RecipeCategory.MISC, TransitReportBlocks.TRANSIT_CHART_ITEM)
			//         .pattern("AEA")
			//         .pattern("ECE")
			//         .pattern("AGA")
			//         .define('A', Items.AMETHYST_SHARD)
			//         .define('E', Items.ECHO_SHARD)
			//         .define('C', Items.CLOCK)
			//         .define('G', Items.GLOW_INK_SAC)
			//         .unlockedBy("has_echo_shard", has(Items.ECHO_SHARD))
			//         .save(exporter, JollyalchemyTransitReport.id("transit_chart"));
		}
	}

	// Generates the block's self-drop loot table (BLOCK-05, GEN-04). The no-argument
	// generate() below is the abstract method to implement; a second, already-implemented
	// generate(BiConsumer<...>) exists on this same class and must not be overridden - it
	// calls this one internally and additionally performs strict-validation bookkeeping that
	// an override would silently discard. See 03-RESEARCH.md Pattern 2, Pitfall 1.
	private static final class TransitChartLootTableProvider extends FabricBlockLootTableProvider {
		private TransitChartLootTableProvider(FabricDataOutput output) {
			super(output);
		}

		@Override
		public void generate() {
			dropSelf(TransitReportBlocks.TRANSIT_CHART);
		}
	}
}
