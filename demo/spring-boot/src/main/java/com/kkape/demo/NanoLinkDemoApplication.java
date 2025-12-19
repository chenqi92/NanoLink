package com.kkape.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * NanoLink Spring Boot Demo Application
 *
 * This demo shows how to integrate NanoLink SDK with Spring Boot
 * to receive metrics from monitoring agents.
 */
@SpringBootApplication
public class NanoLinkDemoApplication {

    public static void main(String[] args) {
        SpringApplication.run(NanoLinkDemoApplication.class, args);
    }
}
