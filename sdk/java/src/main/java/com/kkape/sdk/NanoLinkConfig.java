package com.kkape.sdk;

/**
 * Configuration for NanoLink gRPC Server
 */
public class NanoLinkConfig {
    /** Default gRPC port for agent connections */
    public static final int DEFAULT_GRPC_PORT = 39100;

    /**
     * Default token validator that accepts every agent with READ_ONLY. Exposed as
     * a named constant so the server can detect when no real validator was set and
     * warn about the insecure posture. Do NOT use in production.
     */
    public static final TokenValidator DEFAULT_TOKEN_VALIDATOR =
            token -> new TokenValidator.ValidationResult(true, 0);

    private int grpcPort = DEFAULT_GRPC_PORT;
    private String tlsCertPath;
    private String tlsKeyPath;
    private TokenValidator tokenValidator = DEFAULT_TOKEN_VALIDATOR;

    public int getGrpcPort() {
        return grpcPort;
    }

    public void setGrpcPort(int grpcPort) {
        this.grpcPort = grpcPort;
    }

    public String getTlsCertPath() {
        return tlsCertPath;
    }

    public void setTlsCertPath(String tlsCertPath) {
        this.tlsCertPath = tlsCertPath;
    }

    public String getTlsKeyPath() {
        return tlsKeyPath;
    }

    public void setTlsKeyPath(String tlsKeyPath) {
        this.tlsKeyPath = tlsKeyPath;
    }

    public TokenValidator getTokenValidator() {
        return tokenValidator;
    }

    public void setTokenValidator(TokenValidator tokenValidator) {
        this.tokenValidator = tokenValidator;
    }
}
