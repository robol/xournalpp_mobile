package it.robol.xournal.mobile;

import java.nio.file.*;
import java.util.*;

/** Runs without Android to inject failures at the exact truncating-write boundary. */
public final class SafOverwriteFaultTest {
    private static final byte[] OLD = {1, 2, 3}, NEW = {4, 5, 6, 7};
    private static final class Store implements SafOverwrite.Recovery {
        final Path root;
        int retained;
        int failAt;
        boolean failCleanup;
        Store() throws Exception { root = Files.createTempDirectory("saf-recovery-"); }
        public String retain(byte[] bytes, String kind) throws Exception {
            if (++retained == failAt) throw new java.io.IOException("disk full");
            Files.write(root.resolve(kind), bytes);
            return kind;
        }
        public void remove(String id) throws Exception {
            if (failCleanup) throw new java.io.IOException("cleanup failed");
            Files.delete(root.resolve(id));
        }
        void bothSurvivedRestart() throws Exception {
            // Reopen the persisted bytes without reusing the writer's memory.
            check(Arrays.equals(Files.readAllBytes(root.resolve("original")), OLD));
            check(Arrays.equals(Files.readAllBytes(root.resolve("edited")), NEW));
        }
        void close() throws Exception {
            try (var paths = Files.list(root)) { for (Path path : paths.toList()) Files.delete(path); }
            Files.delete(root);
        }
    }
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }
    public static void main(String[] args) throws Exception {
        for (String fault : List.of("success", "short", "throw", "permissions", "verify", "death", "backup1", "backup2", "read", "cleanup")) {
            Store store = new Store();
            store.failAt = fault.equals("backup1") ? 1 : fault.equals("backup2") ? 2 : 0;
            store.failCleanup = fault.equals("cleanup");
            byte[][] document = {OLD.clone()};
            int[] writes = {0}, reads = {0};
            try {
                SafOverwrite.write(new SafOverwrite.Document() {
                    public byte[] read() throws Exception {
                        reads[0]++;
                        if (fault.equals("read") || fault.equals("verify") && reads[0] > 1) throw new SecurityException("read revoked");
                        return document[0].clone();
                    }
                    public void write(byte[] bytes) throws Exception {
                        writes[0]++;
                        store.bothSurvivedRestart(); // Required BEFORE opening a truncating stream.
                        document[0] = new byte[0];
                        switch (fault) {
                            case "short": document[0] = new byte[]{bytes[0]}; return;
                            case "throw": throw new java.io.IOException("provider write failure");
                            case "permissions": throw new SecurityException("write revoked");
                            case "death": throw new Error("simulated abrupt process termination");
                            default: document[0] = bytes.clone();
                        }
                    }
                }, store, NEW);
                check(fault.equals("success") || fault.equals("cleanup"));
                check(Arrays.equals(document[0], NEW));
                if (fault.equals("success")) {
                    try (var files = Files.list(store.root)) { check(files.count() == 0); }
                } else store.bothSurvivedRestart();
            } catch (SafOverwrite.Failure error) {
                check(!fault.equals("success"));
                if (fault.equals("read") || fault.startsWith("backup")) {
                    check(writes[0] == 0);
                    check(Arrays.equals(document[0], OLD));
                } else {
                    check(error.recoveryAvailable);
                    store.bothSurvivedRestart();
                }
            } catch (Error death) {
                if (!fault.equals("death") || death instanceof AssertionError) throw death;
                store.bothSurvivedRestart();
            } finally { store.close(); }
            System.out.println("PASS " + fault);
        }
    }
}
