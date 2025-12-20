import Navbar from '../components/Navbar'
import Footer from '../components/Footer'

export default function Support() {
    return (
        <div className="min-h-screen bg-black text-white selection:bg-primary selection:text-white">
            <Navbar />
            <main className="max-w-[800px] mx-auto px-6 pt-32 pb-20 min-h-[60vh] flex flex-col justify-center text-center">
                <h1 className="text-4xl font-display font-bold mb-6">How can I help?</h1>
                <p className="text-xl text-gray-400 mb-12 max-w-xl mx-auto">
                    I'm Emre Tekneci, the developer behind Mneme. If you're encountering issues or have feature requests, please reach out.
                </p>

                <div className="bg-[#1c1c1e] border border-white/10 rounded-2xl p-8 max-w-md mx-auto w-full">
                    <h3 className="text-lg font-medium text-white mb-2">Email Me</h3>
                    <p className="text-gray-400 mb-6">I typically respond within 24 hours.</p>
                    <a href="mailto:teknecci@gmail.com" className="inline-block w-full bg-white text-black font-bold py-3 rounded-xl hover:scale-105 transition-transform">
                        teknecci@gmail.com
                    </a>
                </div>
            </main>
            <Footer />
        </div>
    )
}
