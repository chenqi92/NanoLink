package com.kkape.sdk;

/**
 * Configuration for NanoLink Server
 */
public class NanoLinkConfig {
    /** Default gRPC port for agent connections */
    public static final int DEFAULT_GRPC_PORT = 39100;

    /** Default WebSocket/HTTP port for agent connections and API */
    public static final int DEFAULT_WS_PORT = 9100;

    private int grpcPort = DEFAULT_GRPC_PORT;
    private int wsPort = DEFAULT_WS_PORT;
    private String tlsCertPath;
    private String tlsKeyPath;
    private TokenValidator tokenValidator = token -> new TokenValidator.ValidationResult(true, 0);

    public int getGrpcPort() {
        return grpcPort;
    }

    public void setGrpcPort(int grpcPort) {
        this.grpcPort = grpcPort;
    }

    public int getWsPort() {
        return wsPort;
    }

    public void setWsPort(int wsPort) {
        this.wsPort = wsPort;
    }

    /**
     * @deprecated Use {@link #getGrpcPort()} for agent connections or
     *             {@link #getWsPort()} for dashboard
     */
    @Deprecated
    public int getPort() {
        return wsPort;
    }

    /**
     * @deprecated Use {@link #setGrpcPort(int)} for agent connections or
     *             {@link #setWsPort(int)} for dashboard
     */
    @Deprecated
    public void setPort(int port) {
        this.wsPort = port;
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
