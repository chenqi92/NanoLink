package com.kkape.sdk;

/**
 * Configuration for NanoOps gRPC Server
 */
public class NanoLinkConfig {
    /** Default gRPC port for agent connections */
    public static final int DEFAULT_GRPC_PORT = 39100;

    /**
     * Default token validator fails closed until the embedding application
     * supplies an authentication policy.
     */
    public static final TokenValidator DEFAULT_TOKEN_VALIDATOR =
            token -> TokenValidator.ValidationResult.failure("no token validator configured");

    private int grpcPort = DEFAULT_GRPC_PORT;
    private String tlsCertPath;
    private String tlsKeyPath;
    private TokenValidator tokenValidator = DEFAULT_TOKEN_VALIDATOR;
    private boolean requireAuthentication = true;

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

    public boolean isRequireAuthentication() {
        return requireAuthentication;
    }

    public void setRequireAuthentication(boolean requireAuthentication) {
        this.requireAuthentication = requireAuthentication;
    }
}
