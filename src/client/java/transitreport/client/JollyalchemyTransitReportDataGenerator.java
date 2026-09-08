package transitreport.client;

import net.fabricmc.fabric.api.datagen.v1.DataGeneratorEntrypoint;
import net.fabricmc.fabric.api.datagen.v1.FabricDataGenerator;
import net.fabricmc.fabric.api.datagen.v1.FabricDataOutput;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricLanguageProvider;

import transitreport.JollyalchemyTransitReport;

public class JollyalchemyTransitReportDataGenerator implements DataGeneratorEntrypoint {
	@Override
	public void onInitializeDataGenerator(FabricDataGenerator fabricDataGenerator) {
		FabricDataGenerator.Pack pack = fabricDataGenerator.createPack();
		pack.addProvider(TransitReportLanguageProvider::new);
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
		}
	}
}
