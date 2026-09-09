package transitreport.config;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonSyntaxException;

import net.fabricmc.loader.api.FabricLoader;

import transitreport.JollyalchemyTransitReport;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Gson-backed config POJO for this mod's base URL template and refresh interval (CFG-01,
 * CFG-02). No {@code net.minecraft.client.*} import of any kind -- stays common/src-main so it
 * can be loaded from server-capable code as well as client code (PROJECT.md's multiplayer
 * forward-compat constraint).
 *
 * <p>Validation is deliberately minimal -- type/shape checks only (D-13): {@code baseUrl} must
 * be a non-empty string, {@code refreshIntervalSeconds} must be positive. Any parse or
 * validation failure resets ALL fields to defaults, not just the offending one (D-11), and the
 * bad file on disk is overwritten with fresh defaults (D-12) -- the same {@link #writeDefaults}
 * path handles both "file missing" (first run) and "file malformed" (recovery) identically.
 */
public class TransitConfig {

    private static final String CONFIG_FILE_NAME = "transit-config.json";

    public static final String DEFAULT_BASE_URL =
            "https://human-design-4u01.onrender.com/api/viz/transit?date={date}&time={time}&width=512&height=800&transparent=false";
    public static final int DEFAULT_REFRESH_INTERVAL_SECONDS = 60;

    public String baseUrl = DEFAULT_BASE_URL;
    public int refreshIntervalSeconds = DEFAULT_REFRESH_INTERVAL_SECONDS;

    /**
     * Loads config from the standard Fabric config directory. Public entry point for
     * production callers (e.g. {@code JollyalchemyTransitReportClient}).
     */
    public static TransitConfig load() {
        return load(FabricLoader.getInstance().getConfigDir());
    }

    /**
     * Loads config from {@code configDir/transit-config.json}, resolving relative to the given
     * directory. Package-private so {@code TransitConfigTest} can exercise the full
     * parse/validate/default-fallback logic without a running Fabric environment.
     */
    static TransitConfig load(Path configDir) {
        Path configFile = configDir.resolve(CONFIG_FILE_NAME);

        if (!Files.exists(configFile)) {
            // First run -- not an error, no warning needed (CFG-01).
            return writeDefaults(configFile);
        }

        try {
            String json = Files.readString(configFile);
            TransitConfig config = new Gson().fromJson(json, TransitConfig.class);

            if (config == null || config.baseUrl == null || config.baseUrl.isEmpty()
                    || config.refreshIntervalSeconds <= 0) {
                String reason = config == null
                        ? "parsed to null"
                        : (config.baseUrl == null || config.baseUrl.isEmpty()
                                ? "validation failed: baseUrl empty"
                                : "validation failed: refreshIntervalSeconds <= 0");
                JollyalchemyTransitReport.LOGGER.warn(
                        "Config file was malformed ({}); using defaults and rewriting {}",
                        reason, CONFIG_FILE_NAME);
                return writeDefaults(configFile);
            }

            return config;
        } catch (IOException e) {
            JollyalchemyTransitReport.LOGGER.warn(
                    "Config file could not be read ({}); using defaults and rewriting {}",
                    e.getMessage(), CONFIG_FILE_NAME);
            return writeDefaults(configFile);
        } catch (JsonSyntaxException e) {
            JollyalchemyTransitReport.LOGGER.warn(
                    "Config file was malformed (JSON parse error: {}); using defaults and rewriting {}",
                    e.getMessage(), CONFIG_FILE_NAME);
            return writeDefaults(configFile);
        }
    }

    private static TransitConfig writeDefaults(Path configFile) {
        TransitConfig defaults = new TransitConfig();
        try {
            Files.createDirectories(configFile.getParent());
            // disableHtmlEscaping(): Gson's default escapes '&'/'='/'<'/'>' as unicode
            // sequences to be HTML-safe. This config value is a URL template full of '&' and
            // '=' (D-02) that a human is expected to read and hand-edit -- HTML-safe escaping
            // would silently turn "date={date}&time={time}" into unreadable "&" noise.
            Files.writeString(configFile,
                    new GsonBuilder().disableHtmlEscaping().setPrettyPrinting().create().toJson(defaults));
        } catch (IOException e) {
            JollyalchemyTransitReport.LOGGER.error("Failed to write default config file", e);
        }
        return defaults;
    }
}
