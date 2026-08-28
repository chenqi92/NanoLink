package com.kkape.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * NanoOps Spring Boot Demo Application
 * <p>
 * This demo shows how to integrate NanoOps SDK with Spring Boot
 * to receive metrics from monitoring agents.
 */
@SpringBootApplication
public class NanoLinkDemoApplication {

    public static void main(String[] args) {
        SpringApplication.run(NanoLinkDemoApplication.class, args);
    }
}
