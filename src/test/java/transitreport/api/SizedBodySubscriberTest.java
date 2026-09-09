package transitreport.api;

import org.junit.jupiter.api.Test;

import java.nio.ByteBuffer;
import java.util.List;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Flow;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Unit tests for {@link SizedBodySubscriber}. Exercised directly against a hand-rolled
 * {@link Flow.Subscription} test double -- no server, no network, per 05-01-PLAN.md's
 * behavior spec.
 */
class SizedBodySubscriberTest {

    /** Minimal test double recording whether cancel() was invoked. */
    private static class RecordingSubscription implements Flow.Subscription {
        private int cancelCount = 0;

        @Override
        public void request(long n) {
            // no-op: this test double doesn't need to honor backpressure
        }

        @Override
        public void cancel() {
            cancelCount++;
        }

        int cancelCount() {
            return cancelCount;
        }
    }

    @Test
    void withinLimitDeliversFullBodyAndNeverCancels()
            throws ExecutionException, InterruptedException, TimeoutException {
        SizedBodySubscriber subscriber = new SizedBodySubscriber(100);
        RecordingSubscription subscription = new RecordingSubscription();

        subscriber.onSubscribe(subscription);
        byte[] chunk = new byte[50];
        for (int i = 0; i < chunk.length; i++) {
            chunk[i] = (byte) i;
        }
        subscriber.onNext(List.of(ByteBuffer.wrap(chunk)));
        subscriber.onComplete();

        // Bounded wait: a broken/incomplete implementation must fail fast, not hang the suite.
        byte[] result = subscriber.getBody().toCompletableFuture().get(5, TimeUnit.SECONDS);
        assertArrayEquals(chunk, result);
        assertFalse(subscriber.isSizeExceeded());
        assertEquals(0, subscription.cancelCount());
    }

    @Test
    void overLimitCancelsSubscriptionAndCompletesExceptionally() {
        SizedBodySubscriber subscriber = new SizedBodySubscriber(10);
        RecordingSubscription subscription = new RecordingSubscription();

        subscriber.onSubscribe(subscription);
        byte[] chunk = new byte[20];
        subscriber.onNext(List.of(ByteBuffer.wrap(chunk)));

        assertTrue(subscriber.isSizeExceeded());
        assertEquals(1, subscription.cancelCount());
        assertTrue(subscriber.getBody().toCompletableFuture().isCompletedExceptionally());
        assertThrows(Exception.class, () -> {
            try {
                // Bounded wait: a broken/incomplete implementation must fail fast, not hang.
                subscriber.getBody().toCompletableFuture().get(5, TimeUnit.SECONDS);
            } catch (ExecutionException | InterruptedException | TimeoutException e) {
                throw new CompletionException(e);
            }
        });
    }
}
