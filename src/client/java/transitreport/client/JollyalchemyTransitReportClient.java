package transitreport.client;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.rendering.v1.BlockEntityRendererRegistry;
import net.minecraft.client.Minecraft;

import transitreport.JollyalchemyTransitReport;
import transitreport.TransitReportBlocks;
import transitreport.api.TransitApiClient;
import transitreport.config.TransitConfig;

public class JollyalchemyTransitReportClient implements ClientModInitializer {
	@Override
	public void onInitializeClient() {
		// This entrypoint is suitable for setting up client-specific logic, such as rendering.
		BlockEntityRendererRegistry.register(TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY,
				context -> new TransitChartRenderer());

		// D-05: exactly one one-shot verification fetch at client startup, proving the
		// config-load-then-async-fetch pipeline works in isolation from the block/renderer/
		// texture track (Phases 2-4). No debug command, no keybind, no recurring timer --
		// Phase 8 builds the real scheduler. This callback is the only place in this phase's
		// new code that calls Minecraft.getInstance().execute() -- TransitApiClient itself
		// never imports net.minecraft.client.Minecraft.
		TransitConfig config = TransitConfig.load();
		TransitApiClient apiClient = new TransitApiClient();
		apiClient.fetchChart(config.baseUrl, new TransitApiClient.ChartCallback() {
			@Override
			public void onSuccess(byte[] pngBytes) {
				Minecraft.getInstance().execute(() ->
						JollyalchemyTransitReport.LOGGER.info(
								"Startup chart fetch succeeded: {} bytes", pngBytes.length));
				apiClient.shutdown();
			}

			@Override
			public void onFailure(Throwable error) {
				Minecraft.getInstance().execute(() ->
						JollyalchemyTransitReport.LOGGER.warn(
								"Startup chart fetch failed: {}", error.getMessage()));
				apiClient.shutdown();
			}
		});
	}
}