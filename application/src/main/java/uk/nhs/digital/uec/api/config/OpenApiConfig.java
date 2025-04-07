package uk.nhs.digital.uec.api.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.servers.Server;

@Configuration
public class OpenApiConfig {

  @Value("${api.version}")
  private String apiVersion;

  @Value("${api.title}")
  private String title;

  @Value("${api.description}")
  private String description;

  @Bean
  public OpenAPI customOpenAPI() {
    return new OpenAPI()
      .info(new Info()
        .title(title)
        .version(apiVersion)
        .description(description))
      .addServersItem(new Server().url("/"));
  }
}
