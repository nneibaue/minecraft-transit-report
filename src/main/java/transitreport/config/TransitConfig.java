package transitreport.config;

import java.nio.file.Path;

/**
 * RED-phase stub. Compiles so {@code TransitConfigTest} can run, but deliberately does not
 * implement CFG-01/02/03/D-11/D-12/D-13 -- {@link #load(Path)} always returns bare defaults
 * without ever touching disk. Replaced with the real implementation in the GREEN commit.
 */
public class TransitConfig {

    public static final String DEFAULT_BASE_URL =
            "https://human-design-4u01.onrender.com/api/viz/transit?date={date}&time={time}&width=512&height=800&transparent=false";
    public static final int DEFAULT_REFRESH_INTERVAL_SECONDS = 60;

    public String baseUrl = DEFAULT_BASE_URL;
    public int refreshIntervalSeconds = DEFAULT_REFRESH_INTERVAL_SECONDS;

    public static TransitConfig load() {
        throw new UnsupportedOperationException("RED stub: not yet implemented");
    }

    static TransitConfig load(Path configDir) {
        // Deliberately incomplete: does not read, write, or validate anything yet.
        return new TransitConfig();
    }
}
