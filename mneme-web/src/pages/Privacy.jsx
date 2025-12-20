import Navbar from '../components/Navbar'
import Footer from '../components/Footer'

export default function Privacy() {
    return (
        <div className="min-h-screen bg-black text-white selection:bg-primary selection:text-white">
            <Navbar />
            <main className="max-w-[800px] mx-auto px-6 pt-32 pb-20">
                <h1 className="text-4xl font-display font-bold mb-8">Privacy Policy</h1>

                <div className="prose prose-invert prose-lg text-gray-300">
                    <p className="lead text-xl text-white mb-8">
                        I believe that your thoughts, health data, and schedule are deeply personal.
                        That's why I built Mneme to be <span className="text-primary font-bold">100% private by design</span>.
                    </p>

                    <h3 className="text-2xl font-bold text-white mt-8 mb-4">Data Processing</h3>
                    <p>
                        Mneme utilizes <strong>Apple Intelligence</strong> and strictly on-device processing algorithms.
                        All natural language understanding, pattern recognition, and correlation analysis happen directly on your iPhone.
                        <strong>Your data never leaves your device</strong> to be processed by our servers.
                    </p>

                    <h3 className="text-2xl font-bold text-white mt-8 mb-4">HealthKit Integration</h3>
                    <p>
                        Mneme integrates with Apple HealthKit to provide you with insights about your well-being.
                        I read data such as sleep analysis, heart rate, and activity energy to visualize correlations between your productivity and health.
                        This data is:
                    </p>
                    <ul className="list-disc pl-6 space-y-2 my-4">
                        <li>Used exclusively for displaying graphs and generating local summaries.</li>
                        <li>Stored only within the refined local database on your device.</li>
                        <li>Never shared with third-party advertising networks.</li>
                        <li>Never sold to data brokers.</li>
                    </ul>

                    <h3 className="text-2xl font-bold text-white mt-8 mb-4">Calendar & Reminders</h3>
                    <p>
                        I adhere to strict privacy standards when accessing your Apple Calendar and Reminders.
                        This access is used solely to allow you to view and manage your schedule within the Mneme interface.
                    </p>

                    <h3 className="text-2xl font-bold text-white mt-8 mb-4">Your Rights</h3>
                    <p>
                        Since I do not store your data on cloud servers, you retain complete ownership.
                        Deleting the application removes all locally stored analysis caches.
                        Your original health and calendar data remains safe in your Apple apps.
                    </p>

                    <h3 className="text-2xl font-bold text-white mt-8 mb-4">Contact</h3>
                    <p>
                        If you have any questions regarding privacy, please contact me at teknecci@gmail.com.
                    </p>
                </div>
            </main>
            <Footer />
        </div>
    )
}
