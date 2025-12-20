import { motion } from 'framer-motion'
import { Lock } from 'lucide-react'

export default function Hero() {
    return (
        <section className="pt-32 pb-16 md:pt-48 md:pb-32 text-center relative overflow-hidden">
            <div className="max-w-[1080px] mx-auto px-6 relative z-10">
                <motion.h1
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
                    className="text-5xl md:text-7xl font-display font-bold tracking-tight mb-6 leading-tight"
                >
                    Profoundly <span className="text-gradient">Intuitive.</span>
                </motion.h1>

                <motion.p
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.8, delay: 0.1, ease: [0.16, 1, 0.3, 1] }}
                    className="text-xl text-gray-400 max-w-2xl mx-auto mb-10 leading-relaxed font-light"
                >
                    The intelligent workspace that synthesizes your health, calendar, and memories.
                </motion.p>

                <motion.div
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.8, delay: 0.2, ease: "circOut" }}
                    className="flex justify-center mb-10"
                >
                    <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full border border-white/10 bg-white/5 backdrop-blur-md">
                        <Lock size={14} className="text-primary" />
                        <span className="text-sm font-medium text-gray-200">100% On-Device AI. Private by Design.</span>
                    </div>
                </motion.div>

                <motion.div
                    initial={{ opacity: 0, scale: 0.95 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ duration: 0.5, delay: 0.2 }}
                >
                    <a href="#" className="inline-block bg-white text-black px-8 py-3 rounded-full text-lg font-medium hover:scale-105 transition-transform duration-300">
                        Download on App Store
                    </a>
                </motion.div>


            </div>
        </section >
    )
}
