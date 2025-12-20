import { Link } from 'react-router-dom'

export default function Footer() {
    return (
        <footer className="border-t border-white/10 bg-black py-12 mt-20">
            <div className="max-w-[1080px] mx-auto px-6 text-center">
                <div className="font-logo font-semibold text-2xl mb-6 tracking-tight">Mneme</div>
                <div className="flex justify-center gap-6 mb-8 text-sm text-gray-400">
                    <Link to="/privacy" className="hover:text-primary transition-colors">Privacy Policy</Link>
                    <a href="https://github.com/teknetekne/Mneme" target="_blank" rel="noopener noreferrer" className="hover:text-primary transition-colors">GitHub</a>
                    <Link to="/support" className="hover:text-primary transition-colors">Support</Link>
                </div>
                <p className="text-xs text-gray-600">Built by <a href="https://github.com/teknetekne" target="_blank" rel="noopener noreferrer" className="underline hover:text-primary transition-colors">tekne</a> with love and a little bit of a nervous breakdown.</p>
            </div>
        </footer>
    )
}
