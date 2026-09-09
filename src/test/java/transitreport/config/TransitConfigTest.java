package transitreport.config;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Unit tests for {@link TransitConfig#load(Path)}. No FabricLoader or Fabric runtime is
 * involved -- these tests call the package-private, path-injectable load method directly
 * against a JUnit-managed temp directory, per 05-01-PLAN.md's behavior spec.
 */
class TransitConfigTest {

    @Test
    void missingFileYieldsDefaultsAndWritesFile(@TempDir Path tempDir) throws IOException {
        Path configFile = tempDir.resolve("transit-config.json");

        TransitConfig config = TransitConfig.load(tempDir);

        assertEquals(TransitConfig.DEFAULT_BASE_URL, config.baseUrl);
        assertEquals(TransitConfig.DEFAULT_REFRESH_INTERVAL_SECONDS, config.refreshIntervalSeconds);
        assertTrue(Files.exists(configFile), "expected transit-config.json to be written to disk");
    }

    @Test
    void validCustomJsonIsReturnedAndFileIsNotRewritten(@TempDir Path tempDir) throws IOException {
        Path configFile = tempDir.resolve("transit-config.json");
        String customJson = "{\"baseUrl\":\"https://example.test/x\",\"refreshIntervalSeconds\":30}";
        Files.writeString(configFile, customJson);
        long originalModifiedTime = Files.getLastModifiedTime(configFile).toMillis();

        TransitConfig config = TransitConfig.load(tempDir);

        assertEquals("https://example.test/x", config.baseUrl);
        assertEquals(30, config.refreshIntervalSeconds);
        String onDiskAfterLoad = Files.readString(configFile);
        assertEquals(customJson, onDiskAfterLoad, "file must not be rewritten when contents are valid");
        assertEquals(originalModifiedTime, Files.getLastModifiedTime(configFile).toMillis());
    }

    @Test
    void syntacticallyInvalidJsonYieldsDefaultsForBothFieldsAndOverwritesFile(@TempDir Path tempDir) throws IOException {
        Path configFile = tempDir.resolve("transit-config.json");
        Files.writeString(configFile, "{not json");

        TransitConfig config = TransitConfig.load(tempDir);

        assertEquals(TransitConfig.DEFAULT_BASE_URL, config.baseUrl);
        assertEquals(TransitConfig.DEFAULT_REFRESH_INTERVAL_SECONDS, config.refreshIntervalSeconds);
        String onDiskAfterLoad = Files.readString(configFile);
        assertFalse(onDiskAfterLoad.contains("{not json"), "malformed file must be overwritten with fresh defaults");
        assertTrue(onDiskAfterLoad.contains(TransitConfig.DEFAULT_BASE_URL));
    }

    @Test
    void nonPositiveRefreshIntervalResetsBothFieldsToDefaults(@TempDir Path tempDir) throws IOException {
        Path configFile = tempDir.resolve("transit-config.json");
        Files.writeString(configFile, "{\"baseUrl\":\"https://example.test/valid\",\"refreshIntervalSeconds\":-5}");

        TransitConfig config = TransitConfig.load(tempDir);

        assertEquals(TransitConfig.DEFAULT_BASE_URL, config.baseUrl,
                "D-11: one bad field must reset ALL fields to defaults, not just the invalid one");
        assertEquals(TransitConfig.DEFAULT_REFRESH_INTERVAL_SECONDS, config.refreshIntervalSeconds);
    }
}
