import { motion } from 'framer-motion'
import { Link, useLocation } from 'react-router-dom'

export default function Navbar() {
    const location = useLocation()
    const isHome = location.pathname === '/'

    return (
        <motion.nav
            initial={{ y: -100 }}
            animate={{ y: 0 }}
            className="absolute top-0 inset-x-0 z-50 h-24 bg-transparent"
        >
            <div className="max-w-[1080px] mx-auto px-6 h-full flex items-center justify-between">
                <Link to="/" className="flex items-center gap-3">
                    <img src="/assets/mneme-logo.png" alt="Mneme" className="h-8 w-auto" />
                    <span className="font-logo font-semibold text-2xl tracking-tight">Mneme</span>
                </Link>

                <div className="hidden md:flex items-center gap-8">
                    {isHome && (
                        <>
                            {/* <a href="#overview" className="text-sm font-medium text-gray-400 hover:text-white transition-colors">Overview</a> */}
                            {/* <a href="#tech-specs" className="text-sm font-medium text-gray-400 hover:text-white transition-colors">Tech Specs</a> */}
                        </>
                    )}
                    {!isHome && <Link to="/" className="text-sm font-medium text-gray-400 hover:text-white transition-colors">Home</Link>}

                    <button className="bg-white text-black px-5 py-2 rounded-full text-sm font-medium hover:scale-105 transition-transform">
                        Download
                    </button>
                </div>
            </div>
        </motion.nav>
    )
}
