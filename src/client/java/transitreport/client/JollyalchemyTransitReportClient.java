package transitreport.client;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.rendering.v1.BlockEntityRendererRegistry;

import transitreport.TransitReportBlocks;

public class JollyalchemyTransitReportClient implements ClientModInitializer {
	@Override
	public void onInitializeClient() {
		// This entrypoint is suitable for setting up client-specific logic, such as rendering.
		BlockEntityRendererRegistry.register(TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY,
				context -> new TransitChartRenderer());
	}
}