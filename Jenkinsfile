@Library('shared-lib') _

pipeline{

    agent any

    stages{

        stage('Git Checkout'){

            steps{

                script{

                    gitCheckout(
                        branch: "main",
                        url: "https://github.com/skull-Atul/java.git"
                    )
                }
            }
        }
    }
}