package transitreport.client;

import net.fabricmc.fabric.api.datagen.v1.DataGeneratorEntrypoint;
import net.fabricmc.fabric.api.datagen.v1.FabricDataGenerator;
import net.fabricmc.fabric.api.datagen.v1.FabricDataOutput;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricLanguageProvider;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricModelProvider;

import net.minecraft.data.models.BlockModelGenerators;
import net.minecraft.data.models.ItemModelGenerators;
import net.minecraft.data.models.model.TextureSlot;
import net.minecraft.data.models.model.TexturedModel;
import net.minecraft.resources.ResourceLocation;

import transitreport.JollyalchemyTransitReport;
import transitreport.TransitReportBlocks;

public class JollyalchemyTransitReportDataGenerator implements DataGeneratorEntrypoint {
	@Override
	public void onInitializeDataGenerator(FabricDataGenerator fabricDataGenerator) {
		FabricDataGenerator.Pack pack = fabricDataGenerator.createPack();
		pack.addProvider(TransitReportLanguageProvider::new);
		pack.addProvider(TransitChartModelProvider::new);
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
}
