package transitreport.client;

import com.mojang.blaze3d.platform.NativeImage;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;
import com.mojang.math.Axis;

import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.LightTexture;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.blockentity.BlockEntityRenderer;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.minecraft.core.Direction;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;

import org.joml.Matrix3f;
import org.joml.Matrix4f;

import java.io.IOException;
import java.io.InputStream;

import transitreport.JollyalchemyTransitReport;
import transitreport.block.entity.TransitChartBlockEntity;

/**
 * Draws the bundled {@code sample-bodygraph.png} on the face of a placed
 * {@link TransitChartBlockEntity}, oversized relative to the block's own footprint, bottom
 * -anchored, oriented per the block's {@code FACING} state, and fully emissive (04-01-PLAN.md
 * Task 1; REND-01 through REND-07).
 *
 * <p>No HTTP, no {@code DynamicTexture}, no runtime {@code NativeImage}-to-texture-upload
 * pipeline exists here -- the bundled PNG is a plain resource-pack texture bound directly by
 * {@link ResourceLocation}, loaded once by Minecraft's normal resource system. The one-shot
 * {@link NativeImage} read in the constructor is a dimension probe only (D-05's "compute height
 * from real pixel dimensions", reused verbatim by Phase 6 for arbitrary live-API image sizes),
 * not a texture upload.
 */
public class TransitChartRenderer implements BlockEntityRenderer<TransitChartBlockEntity> {
	// Correction 8 (04-01-PLAN.md): a directly-bound, non-block-model texture ResourceLocation
	// must include the full "textures/..." prefix and the ".png" suffix.
	private static final ResourceLocation TEXTURE =
			JollyalchemyTransitReport.id("textures/block/transit_chart.png");

	// Fixed anchor width; height is computed dynamically below, aspect-preserving.
	// User-directed override of 04-CONTEXT.md D-05's locked 2.0f value (04-01 checkpoint
	// feedback, post visual review in-game): shrunk to 1.5f so the chart reads as a smaller
	// wall panel rather than an oversized poster. Height shrinks proportionally with it since
	// computedHeight is still derived from this value times the image's real aspect ratio.
	private static final float BASE_WIDTH = 1.5f;

	// D-07: small offset in front of the block's face, just enough to avoid z-fighting.
	private static final float Z_OFFSET = 0.02f;

	// Fallback aspect ratio (matches sample-bodygraph.png's known 512x800 dimensions) used only
	// if the one-shot dimension probe below fails to read the bundled texture (T-04-03).
	private static final float DEFAULT_ASPECT = 800.0f / 512.0f;

	private final float computedHeight;

	public TransitChartRenderer() {
		float height;
		try (InputStream stream = Minecraft.getInstance().getResourceManager().open(TEXTURE)) {
			try (NativeImage image = NativeImage.read(stream)) {
				height = BASE_WIDTH * ((float) image.getHeight() / (float) image.getWidth());
			}
		} catch (IOException e) {
			JollyalchemyTransitReport.LOGGER.warn(
					"Failed to read bundled transit chart texture dimensions from {}; falling back to default aspect ratio",
					TEXTURE, e);
			height = BASE_WIDTH * DEFAULT_ASPECT;
		}
		this.computedHeight = height;
	}

	@Override
	public void render(TransitChartBlockEntity blockEntity, float partialTick, PoseStack matrices,
			MultiBufferSource buffers, int packedLight, int packedOverlay) {
		Direction facing = blockEntity.getBlockState().getValue(HorizontalDirectionalBlock.FACING);

		// entityCutoutNoCull: a single decorative face with nothing behind it, so vertex
		// winding order cannot silently backface-cull it (04-01-PLAN.md Task 1 action).
		VertexConsumer vertexConsumer = buffers.getBuffer(RenderType.entityCutoutNoCull(TEXTURE));

		matrices.pushPose();
		matrices.translate(0.5, 0.5, 0.5);
		// Correction 9 (04-01-PLAN.md): sign confirmed/adjusted against the real asymmetric
		// sample-bodygraph.png during Task 2's four-orientation visual pass.
		matrices.mulPose(Axis.YP.rotationDegrees(-facing.toYRot()));
		matrices.translate(-0.5, -0.5, -0.5);

		// Quad authored to face south (+Z, normal (0,0,1)) at zero rotation.
		float x0 = (1.0f - BASE_WIDTH) / 2.0f;
		float x1 = x0 + BASE_WIDTH;
		float y0 = 0.0f; // bottom-anchored (D-08)
		float y1 = computedHeight;
		// Anchored to the near/wall-side face (local z=0), not the far face (04-01 checkpoint
		// feedback, round 3): the invisible block's thin getShape() hitbox (TransitChartBlock)
		// now hugs the face OPPOSITE FACING -- the wall-touching side -- so the rendered quad
		// must anchor there too, or the two end up on opposite faces of the block and the chart
		// floats a full block out into the room instead of hanging flush against the wall.
		float z = Z_OFFSET;

		Matrix4f pose = matrices.last().pose();
		Matrix3f normal = matrices.last().normal();

		vertex(vertexConsumer, pose, normal, x0, y1, z, 0.0f, 0.0f);
		vertex(vertexConsumer, pose, normal, x1, y1, z, 1.0f, 0.0f);
		vertex(vertexConsumer, pose, normal, x1, y0, z, 1.0f, 1.0f);
		vertex(vertexConsumer, pose, normal, x0, y0, z, 0.0f, 1.0f);

		matrices.popPose();
	}

	private static void vertex(VertexConsumer vertexConsumer, Matrix4f pose, Matrix3f normal,
			float x, float y, float z, float u, float v) {
		// LightTexture.FULL_BRIGHT (not LightmapTextureManager.MAX_LIGHT_COORDINATE) and
		// overlayCoords (not overlayCoordinates) - Corrections 3 and 4, 04-01-PLAN.md.
		// packedLight is deliberately ignored (REND-05 requires full brightness regardless of
		// ambient light).
		vertexConsumer.vertex(pose, x, y, z)
				.color(255, 255, 255, 255)
				.uv(u, v)
				.overlayCoords(OverlayTexture.NO_OVERLAY)
				.uv2(LightTexture.FULL_BRIGHT)
				.normal(normal, 0.0f, 0.0f, 1.0f)
				.endVertex();
	}

	@Override
	public boolean shouldRenderOffScreen(TransitChartBlockEntity blockEntity) {
		// Correction 1 (04-01-PLAN.md): this, not any BlockEntity bounding-box override, is
		// REND-03's real mechanism (BeaconRenderer precedent). Default getViewDistance() of 64
		// already satisfies REND-07 (Correction 2) -- not overridden.
		return true;
	}
}
