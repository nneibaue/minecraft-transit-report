package transitreport.api;

import java.net.http.HttpResponse;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.Flow;

/**
 * RED-phase stub. Compiles so {@code SizedBodySubscriberTest} can run, but deliberately does
 * not enforce the size cap (D-09/D-10) yet -- {@link #onNext(List)} is a no-op and
 * {@link #getBody()} never completes. Replaced with the real implementation in the GREEN
 * commit.
 */
public class SizedBodySubscriber implements HttpResponse.BodySubscriber<byte[]> {

    private final CompletableFuture<byte[]> result = new CompletableFuture<>();

    public SizedBodySubscriber(long maxSize) {
        // Deliberately incomplete: maxSize is not enforced yet.
    }

    @Override
    public CompletionStage<byte[]> getBody() {
        return result;
    }

    @Override
    public void onSubscribe(Flow.Subscription subscription) {
        // Deliberately incomplete.
    }

    @Override
    public void onNext(List<java.nio.ByteBuffer> item) {
        // Deliberately incomplete: does not buffer or enforce the cap yet.
    }

    @Override
    public void onError(Throwable throwable) {
        result.completeExceptionally(throwable);
    }

    @Override
    public void onComplete() {
        // Deliberately incomplete: never completes result.
    }

    public boolean isSizeExceeded() {
        return false;
    }
}
