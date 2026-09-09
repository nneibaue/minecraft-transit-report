package transitreport.api;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.http.HttpResponse;
import java.nio.ByteBuffer;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.Flow;

/**
 * A {@link HttpResponse.BodySubscriber} that enforces a hard cap on response size while
 * streaming (D-09/D-10) -- checked in {@link #onNext(List)} against the actual byte count as
 * chunks arrive, not a post-hoc {@code Content-Length} check (which a hostile or broken
 * endpoint can omit or lie about).
 *
 * <p>When the first chunk that would cross the cap arrives, the subscription is cancelled and
 * {@link #getBody()}'s future completes exceptionally -- this is treated as an ordinary fetch
 * failure by {@link TransitApiClient}, not a truncated success (D-10).
 */
public class SizedBodySubscriber implements HttpResponse.BodySubscriber<byte[]> {

    private final long maxSize;
    private final ByteArrayOutputStream buffer = new ByteArrayOutputStream();
    private final CompletableFuture<byte[]> result = new CompletableFuture<>();
    private volatile Flow.Subscription subscription;
    private volatile boolean sizeExceeded = false;

    public SizedBodySubscriber(long maxSize) {
        this.maxSize = maxSize;
    }

    @Override
    public CompletionStage<byte[]> getBody() {
        return result;
    }

    @Override
    public void onSubscribe(Flow.Subscription subscription) {
        this.subscription = subscription;
        subscription.request(Long.MAX_VALUE);
    }

    @Override
    public void onNext(List<ByteBuffer> item) {
        if (sizeExceeded) {
            // cancel() is best-effort/async (Reactive Streams spec) -- a chunk already in
            // flight can still arrive after the cap was flagged, so guard here too.
            return;
        }
        for (ByteBuffer buf : item) {
            if (buffer.size() + buf.remaining() > maxSize) {
                sizeExceeded = true;
                result.completeExceptionally(
                        new IOException("Response exceeded max size of " + maxSize + " bytes"));
                subscription.cancel();
                return;
            }
            byte[] bytes = new byte[buf.remaining()];
            buf.get(bytes);
            buffer.writeBytes(bytes);
        }
    }

    @Override
    public void onError(Throwable throwable) {
        result.completeExceptionally(throwable);
    }

    @Override
    public void onComplete() {
        result.complete(buffer.toByteArray());
    }

    public boolean isSizeExceeded() {
        return sizeExceeded;
    }
}
