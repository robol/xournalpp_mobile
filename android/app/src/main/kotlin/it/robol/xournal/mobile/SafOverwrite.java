package it.robol.xournal.mobile;

import java.util.Arrays;

/** SAF has no portable atomic replacement. Never truncate before recovery is durable. */
public final class SafOverwrite {
    public interface Document {
        byte[] read() throws Exception;
        void write(byte[] bytes) throws Exception;
    }
    public interface Recovery {
        String retain(byte[] bytes, String kind) throws Exception;
        void remove(String id) throws Exception;
    }
    public static final class Failure extends Exception {
        public final boolean recoveryAvailable;
        Failure(Exception cause, boolean recoveryAvailable) {
            super(cause.getMessage(), cause);
            this.recoveryAvailable = recoveryAvailable;
        }
    }
    public static void write(Document document, Recovery recovery, byte[] bytes) throws Failure {
        boolean retained = false;
        try {
            byte[] previous = document.read(); // Read failure must leave the source untouched.
            String original = recovery.retain(previous, "original");
            retained = true;
            String edited = recovery.retain(bytes, "edited");
            document.write(bytes);
            if (!Arrays.equals(bytes, document.read())) {
                throw new java.io.IOException("Provider did not preserve the complete saved document");
            }
            // Never remove recovery on an exception, including verification failure.
            // Cleanup failures leave harmless extra recovery copies.
            try { recovery.remove(original); } catch (Exception ignored) { }
            try { recovery.remove(edited); } catch (Exception ignored) { }
        } catch (Exception error) {
            throw new Failure(error, retained);
        }
    }
    private SafOverwrite() { }
}
