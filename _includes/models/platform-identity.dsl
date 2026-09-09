workspace "Platform Identity" {

    model {
        properties {
          "structurizr.groupSeparator" "/"
        }
        customer = person "Platform Customer" "A customer of the platform with desired workloads" "Customer"

        user = person "Platform User" "A user of the platform accessing platform services" "User"

        group "Platform Services" {
            operator = person "Platform Operator" "Operations staff for the platform" "Platform Staff"
            owner = person "Platform Owner" "Responsible for the platform as a product" "Platform Owner"

            // group "Observability Plane" {

            // }

            group "Security Plane" {
              secrets = softwaresystem "Secrets Engine" "Responsible for managing secrets necessary to securely operate services" "Vault"
              aai = softwaresystem "AAI" "Authorisation service for platform identities" "Keycloak" {
                app = container "Keycloak Application" "Keycloak server" "Quarkus" {

                }
              }
            }

            group "Integration and Delivery Plane" {
              orchestrator = softwaresystem "Platform orchestrator" "Schedules workloads across the resource plane" "Nomad"
            }

            group "Resource Plane" {
              group "Data" {
                softwareSystem "patroni" "Database provisoner and replica controller" "Patroni" {
                  database = container "Database" "Stores user registration information, hashed authentication credentials, access logs, etc." "Postgres Database Schema" "Database"
                }
              }
            }




            }
        }

        // # relationships between people and software systems
        // customer -> internetBankingSystem "Views account balances, and makes payments using"
        // internetBankingSystem -> mainframe "Gets account information from, and makes payments using"
        // internetBankingSystem -> email "Sends e-mail using"
        // email -> customer "Sends e-mails to"
        // customer -> supportStaff "Asks questions to" "Telephone"
        // supportStaff -> mainframe "Uses"
        // customer -> atm "Withdraws cash using"
        // atm -> mainframe "Uses"
        // backoffice -> mainframe "Uses"

        // # relationships to/from containers
        // customer -> webApplication "Visits bigbank.com/ib using" "HTTPS"
        // customer -> singlePageApplication "Views account balances, and makes payments using"
        // customer -> mobileApp "Views account balances, and makes payments using"
        // webApplication -> singlePageApplication "Delivers to the customer's web browser"

        // # relationships to/from components
        // singlePageApplication -> signinController "Makes API calls to" "JSON/HTTPS"
        // singlePageApplication -> accountsSummaryController "Makes API calls to" "JSON/HTTPS"
        // singlePageApplication -> resetPasswordController "Makes API calls to" "JSON/HTTPS"
        // mobileApp -> signinController "Makes API calls to" "JSON/HTTPS"
        // mobileApp -> accountsSummaryController "Makes API calls to" "JSON/HTTPS"
        // mobileApp -> resetPasswordController "Makes API calls to" "JSON/HTTPS"
        // signinController -> securityComponent "Uses"
        // accountsSummaryController -> mainframeBankingSystemFacade "Uses"
        // resetPasswordController -> securityComponent "Uses"
        // resetPasswordController -> emailComponent "Uses"
        // securityComponent -> database "Reads from and writes to" "JDBC"
        // mainframeBankingSystemFacade -> mainframe "Makes API calls to" "XML/HTTPS"
        // emailComponent -> email "Sends e-mail using"

        deploymentEnvironment "Prod" {
            deploymentNode "Developer Laptop" "" "Microsoft Windows 10 or Apple macOS" {
                deploymentNode "Web Browser" "" "Chrome, Firefox, Safari, or Edge" {
                    developerSinglePageApplicationInstance = containerInstance singlePageApplication
                }
                deploymentNode "Docker Container - Web Server" "" "Docker" {
                    deploymentNode "Apache Tomcat" "" "Apache Tomcat 8.x" {
                        developerWebApplicationInstance = containerInstance webApplication
                        developerApiApplicationInstance = containerInstance apiApplication
                    }
                }
                deploymentNode "Docker Container - Database Server" "" "Docker" {
                    deploymentNode "Database Server" "" "Oracle 12c" {
                        developerDatabaseInstance = containerInstance database
                    }
                }
            }
            deploymentNode "Big Bank plc" "" "Big Bank plc data center" "" {
                deploymentNode "bigbank-dev001" "" "" "" {
                    softwareSystemInstance mainframe
                }
            }

        }

        deploymentEnvironment "Live" {
            deploymentNode "Customer's mobile device" "" "Apple iOS or Android" {
                liveMobileAppInstance = containerInstance mobileApp
            }
            deploymentNode "Customer's computer" "" "Microsoft Windows or Apple macOS" {
                deploymentNode "Web Browser" "" "Chrome, Firefox, Safari, or Edge" {
                    liveSinglePageApplicationInstance = containerInstance singlePageApplication
                }
            }

            deploymentNode "Big Bank plc" "" "Big Bank plc data center" {
                deploymentNode "bigbank-web***" "" "Ubuntu 16.04 LTS" "" 4 {
                    deploymentNode "Apache Tomcat" "" "Apache Tomcat 8.x" {
                        liveWebApplicationInstance = containerInstance webApplication
                    }
                }
                deploymentNode "bigbank-api***" "" "Ubuntu 16.04 LTS" "" 8 {
                    deploymentNode "Apache Tomcat" "" "Apache Tomcat 8.x" {
                        liveApiApplicationInstance = containerInstance apiApplication
                    }
                }

                deploymentNode "bigbank-db01" "" "Ubuntu 16.04 LTS" {
                    primaryDatabaseServer = deploymentNode "Oracle - Primary" "" "Oracle 12c" {
                        livePrimaryDatabaseInstance = containerInstance database
                    }
                }
                deploymentNode "bigbank-db02" "" "Ubuntu 16.04 LTS" "Failover" {
                    secondaryDatabaseServer = deploymentNode "Oracle - Secondary" "" "Oracle 12c" "Failover" {
                        liveSecondaryDatabaseInstance = containerInstance database "Failover"
                    }
                }
                deploymentNode "bigbank-prod001" "" "" "" {
                    softwareSystemInstance mainframe
                }
            }

            primaryDatabaseServer -> secondaryDatabaseServer "Replicates data to"
        }
    }

    views {
        systemlandscape "SystemLandscape" {
            include *
            autoLayout
        }

        systemcontext internetBankingSystem "SystemContext" {
            include *
            animation {
                internetBankingSystem
                customer
                mainframe
                email
            }
            autoLayout
        }

        // container internetBankingSystem "Containers" {
        //     include *
        //     animation {
        //         customer mainframe email
        //         webApplication
        //         singlePageApplication
        //         mobileApp
        //         apiApplication
        //         database
        //     }
        //     autoLayout
        // }

        // component apiApplication "Components" {
        //     include *
        //     animation {
        //         singlePageApplication mobileApp database email mainframe
        //         signinController securityComponent
        //         accountsSummaryController mainframeBankingSystemFacade
        //         resetPasswordController emailComponent
        //     }
        //     autoLayout
        // }

        // dynamic apiApplication "SignIn" "Summarises how the sign in feature works in the single-page application." {
        //     singlePageApplication -> signinController "Submits credentials to"
        //     signinController -> securityComponent "Validates credentials using"
        //     securityComponent -> database "select * from users where username = ?"
        //     database -> securityComponent "Returns user data to"
        //     securityComponent -> signinController "Returns true if the hashed password matches"
        //     signinController -> singlePageApplication "Sends back an authentication token to"
        //     autoLayout
        // }

        // deployment internetBankingSystem "Development" "DevelopmentDeployment" {
        //     include *
        //     animation {
        //         developerSinglePageApplicationInstance
        //         developerWebApplicationInstance developerApiApplicationInstance
        //         developerDatabaseInstance
        //     }
        //     autoLayout
        }

        // deployment internetBankingSystem "Live" "LiveDeployment" {
        //     include *
        //     animation {
        //         liveSinglePageApplicationInstance
        //         liveMobileAppInstance
        //         liveWebApplicationInstance liveApiApplicationInstance
        //         livePrimaryDatabaseInstance
        //         liveSecondaryDatabaseInstance
        //     }
        //     autoLayout
        // }

        styles {
            element "Person" {
                color #ffffff
                fontSize 22
                shape Person
            }
            element "Customer" {
                background #08427b
            }

            element "Software System" {
                background #1168bd
                color #ffffff
            }

            element "Container" {
                background #438dd5
                color #ffffff
            }

            element "Component" {
                background #85bbf0
                color #000000
            }

        }
    }
}
